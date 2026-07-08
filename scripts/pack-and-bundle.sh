ghsaBatch=80
ghsaToken="${GHSA_TOKEN:-${GH_TOKEN:-${GITHUB_TOKEN:-}}}"

if [ -z "$ghsaToken" ]; then
    echo "GHSA_TOKEN, GH_TOKEN, or GITHUB_TOKEN is required for GitHub advisory downloads" >&2
    exit 1
fi
VUL_SOURCE_DIR="${VUL_SOURCE_DIR:-vul-source}"

prepare_temp_file() {
    local dest=$1
    local dir base
    dir=$(dirname "$dest")
    base=$(basename "$dest")

    mkdir -p "$dir"
    mktemp "$dir/.${base}.tmp.XXXXXX"
}

prepare_temp_path() {
    local dest=$1
    local tmp

    tmp=$(prepare_temp_file "$dest")
    rm -f "$tmp"
    printf '%s\n' "$tmp"
}

prepare_temp_dir() {
    local dest=$1
    local dir base
    dir=$(dirname "$dest")
    base=$(basename "$dest")

    mkdir -p "$dir"
    mktemp -d "$dir/.${base}.tmp.XXXXXX"
}

publish_file() {
    local source=$1
    local new_file=$2
    local dest_file=$3

    mkdir -p "$(dirname "$dest_file")"
    rm -f "$dest_file"
    mv "$new_file" "$dest_file"
    echo -e "\n*** downloaded $source -> $dest_file ***\n"
}

publish_checkout() {
    local source=$1
    local clone_dir=$2
    local dest_dir=$3
    local _marker_name=${4:-}

    mkdir -p "$(dirname "$dest_dir")"
    rm -rf "$dest_dir"
    mv "$clone_dir" "$dest_dir"
    rm -rf "$dest_dir/.git"
    echo -e "\n*** downloaded $source -> $dest_dir ***\n"
}

download_and_publish_file() {
    local source=$1
    local url=$2
    local dest=$3
    local tmp

    tmp=$(prepare_temp_file "$dest")
    if wget --no-check-certificate -O "$tmp" "$url"; then
        publish_file "$source" "$tmp" "$dest"
    else
        rm -f "$tmp"
        echo "Failed to download $source from $url"
        return 1
    fi
}

download_and_publish_gzip() {
    local source=$1
    local url=$2
    local dest=$3
    local tmp

    tmp=$(prepare_temp_file "$dest")
    if wget --no-check-certificate -O "$tmp" "$url"; then
        if gzip -f "$tmp"; then
            publish_file "$source" "$tmp.gz" "$dest.gz"
        else
            rm -f "$tmp" "$tmp.gz"
            echo "Failed to gzip $source"
            return 1
        fi
    else
        rm -f "$tmp"
        echo "Failed to download $source from $url"
        return 1
    fi
}

download_ghsa() {
    local module=$1
    local datafile=$2
    local query
    local output
    local endCursor
    local hasNextPage=true
    local nextCursor=

    mkdir -p "$(dirname "$datafile")"
    rm -f "$datafile"
    echo -e "\n\n****** Download $module advisories"

    while [ "$hasNextPage" == "true" ]; do
        if ! query=$(
            jq -cn \
                --arg module "$module" \
                --argjson first "$ghsaBatch" \
                --arg cursor "$nextCursor" \
                '{
                  query: "query($ecosystem: SecurityAdvisoryEcosystem!, $first: Int!, $cursor: String) { securityVulnerabilities(orderBy: {field: UPDATED_AT, direction: ASC}, ecosystem: $ecosystem, first: $first, after: $cursor) { totalCount nodes { advisory { ghsaId severity publishedAt updatedAt permalink identifiers { type value } cwes(first: 5) { nodes { cweId } } cvss { score vectorString } summary description references { url } } firstPatchedVersion { identifier } vulnerableVersionRange package { ecosystem name } } pageInfo { endCursor hasNextPage } } }",
                  variables: {
                    ecosystem: $module,
                    first: $first,
                    cursor: (if $cursor == "" then null else $cursor end)
                  }
                }'
        ); then
            echo "Failed to build GraphQL request"
            return 1
        fi

        if ! output=$(curl -fsS -X POST --data "$query" -H "Authorization: bearer $ghsaToken" https://api.github.com/graphql); then
            echo "Failed to send the request"
            return 1
        fi

        hasNextPage=$(jq -c -r '.data.securityVulnerabilities.pageInfo.hasNextPage' <<< "$output")
        endCursor=$(jq -c -r '.data.securityVulnerabilities.pageInfo.endCursor' <<< "$output")

        if [ "$hasNextPage" == "null" ]; then
            echo "Failed to parse the result:"
            echo "$output"
            return 1
        fi

        # Append data to file
        if ! jq -c -r '.data.securityVulnerabilities.nodes[]' <<< "$output" >> "$datafile"; then
            echo "Failed to write to $datafile"
            return 1
        fi

        if [ "$hasNextPage" == "true" ]; then
            nextCursor="$endCursor"
        fi

        echo ${#output} $hasNextPage $endCursor $(wc -l < $datafile)
    done

    return 0
}

download_golang_osv_data() {
    local outputfile="${1:-$VUL_SOURCE_DIR/apps/golang-osv.zip}"
    local osv_repo_url="https://github.com/golang/vulndb.git"
    local clone_dir
    local temp_output

    mkdir -p "$(dirname "$outputfile")"
    clone_dir=$(prepare_temp_dir "$outputfile.vulndb-osv")
    temp_output=$(prepare_temp_path "$outputfile")

    git clone --depth 1 --filter=blob:none --sparse $osv_repo_url "$clone_dir"

    if [ $? -ne 0 ]; then
        echo "Failed to clone repository"
        return 1
    fi

    git -C "$clone_dir" sparse-checkout init --cone
    git -C "$clone_dir" sparse-checkout set data/osv

    if [ ! -d "$clone_dir/data/osv" ]; then
        echo "OSV directory not found"
        rm -rf "$clone_dir"
        return 1
    fi

    local file_count=$(find "$clone_dir/data/osv" -name '*.json' | wc -l)
    echo "Found $file_count OSV files"

    if [ "$file_count" -eq 0 ]; then
        echo "No JSON files found"
        rm -rf "$clone_dir"
        return 1
    fi

    local abs_output
    abs_output="$(cd "$(dirname "$temp_output")" && pwd)/$(basename "$temp_output")"
    (cd "$clone_dir/data/osv" && zip -r "$abs_output" *.json)

    if [ $? -ne 0 ] || [ ! -s "$temp_output" ]; then
        echo "Failed to create archive"
        rm -f "$temp_output"
        rm -rf "$clone_dir"
        return 1
    fi

    echo "Successfully created $(du -h "$temp_output" | cut -f1) archive"
    publish_file "golang_osv" "$temp_output" "$outputfile"
    rm -rf "$clone_dir"
    return 0
}

download_chainguard_osv_v2_data() {
  local outputfile="${1:-$VUL_SOURCE_DIR/chainguard/osv-v2.zip}"
  local index_url="https://advisories.cgr.dev/chainguard/v2/osv/all.json"
  local advisory_base_url="https://advisories.cgr.dev/chainguard/v2/osv"
  local download_dir
  local retries=8
  local retry_delay=10
  local connect_timeout=30
  local max_time=180
  local temp_output

  download_one_chainguard_advisory() {
    local id=$1
    local output=$2
    local advisory_connect_timeout=${3:-$connect_timeout}
    local advisory_retries=${4:-$retries}
    local advisory_retry_delay=${5:-$retry_delay}

    curl -fsSL \
      --connect-timeout "$advisory_connect_timeout" \
      --max-time "$max_time" \
      --retry "$advisory_retries" \
      --retry-delay "$advisory_retry_delay" \
      --retry-all-errors \
      -o "$output" \
      "${advisory_base_url}/${id}.json"
  }

  mkdir -p "$(dirname "$outputfile")"
  download_dir=$(prepare_temp_dir "$outputfile.chainguard")
  temp_output=$(prepare_temp_path "$outputfile")

  echo "Fetching v2 feed index..."
  local index_file="$download_dir/_index.json"
  curl -fsSL -o "$index_file" "$index_url"
  if [ $? -ne 0 ] || [ ! -s "$index_file" ]; then
    echo "Failed to fetch index"
    rm -rf "$download_dir"
    return 1
  fi

  local ids_file="$download_dir/_ids.txt"
  jq -r '.[].id' "$index_file" >"$ids_file"
  if [ $? -ne 0 ] || [ ! -s "$ids_file" ]; then
    echo "Failed to parse index or no advisories found"
    rm -rf "$download_dir"
    return 1
  fi

  local total
  total=$(wc -l <"$ids_file")
  echo "Found $total advisories, downloading..."

  local count=0
  local failed=0
  local failed_ids=()
  while read -r id; do
    count=$((count + 1))
    out="${download_dir}/${id}.json"
    if download_one_chainguard_advisory "$id" "$out"; then
      printf "\r[%d/%d] %s" "$count" "$total" "$id"
    else
      failed=$((failed + 1))
      failed_ids+=("$id")
      printf "\n[%d/%d] FAILED: %s\n" "$count" "$total" "$id" >&2
    fi
  done < "$ids_file"
  echo ""

  if [ "${#failed_ids[@]}" -gt 0 ]; then
    echo "Retrying ${#failed_ids[@]} Chainguard advisories with extended timeout..." >&2

    local retry_failed=0
    local retry_failed_ids=()
    for id in "${failed_ids[@]}"; do
      out="${download_dir}/${id}.json"
      if ! download_one_chainguard_advisory "$id" "$out" 60 10 15; then
        retry_failed=$((retry_failed + 1))
        retry_failed_ids+=("$id")
      fi
    done

    failed=$retry_failed
    if [ "$failed" -gt 0 ]; then
      echo "FAILED $failed advisories after retry:" >&2
      printf '  %s\n' "${retry_failed_ids[@]}" >&2
      rm -rf "$download_dir"
      return 1
    fi
  fi

  rm -f "$index_file" "$ids_file"

  local file_count
  file_count=$(find "$download_dir" -name '*.json' | wc -l)
  echo "Downloaded $file_count / $total advisories ($failed failed)"

  if [ "$file_count" -eq 0 ]; then
    echo "No advisories downloaded"
    rm -rf "$download_dir"
    return 1
  fi

  local abs_output
  abs_output="$(cd "$(dirname "$temp_output")" && pwd)/$(basename "$temp_output")"
  (cd "$download_dir" && zip -r -q "$abs_output" *.json)
  if [ $? -ne 0 ] || [ ! -s "$temp_output" ]; then
    echo "Failed to create archive"
    rm -f "$temp_output"
    rm -rf "$download_dir"
    return 1
  fi

  echo "Successfully created $(du -h "$temp_output" | cut -f1) archive ($file_count advisories)"
  publish_file "osv-v2" "$temp_output" "$outputfile"
  rm -rf "$download_dir"
  return 0
}

fetch_and_process_suse_oval() {
    local source=$1
    local folder=$2
    local file=$3

    local url="https://ftp.suse.com/pub/projects/security/oval/$file"
    local dest="$VUL_SOURCE_DIR/$folder/$file"
    local tmp

    tmp=$(prepare_temp_file "$dest")
    if wget --no-check-certificate -O "$tmp" "$url"; then
        if gzip -t "$tmp" ; then
            publish_file "$source" "$tmp" "$dest"
            echo "Downloaded $file successfully"
        else
            rm -f "$tmp"
            echo "Server returned $status - feed not available: $url"
            return 1
        fi
    else
        rm -f "$tmp"
        echo "Failed to download $file from $url"
        return 1
    fi
}

echo -e "\n******************* update start *******************\n"

mkdir -p "$VUL_SOURCE_DIR"

############## Ubuntu ###############

echo -e "\n*** Update: ubuntu ***\n"
git clone --depth 1 git://git.launchpad.net/ubuntu-cve-tracker "$VUL_SOURCE_DIR/ubuntu-cve-tracker/"

############## Mariner ###############

echo -e "\n*** Update: mariner ***\n"
git clone --depth 1 https://github.com/microsoft/CBL-MarinerVulnerabilityData "$VUL_SOURCE_DIR/mariner-vulnerability/"

############## Debian ###############

echo -e "\n*** Update: debian ***\n"
mkdir -p "$VUL_SOURCE_DIR/debian"
download_and_publish_file "debian" \
    "https://security-tracker.debian.org/tracker/data/json" \
    "$VUL_SOURCE_DIR/debian/debian.json"


############## SUSE ###############

echo -e "\n*** Update: SUSE ***\n"
mkdir -p "$VUL_SOURCE_DIR/suse"

# Define entries as: "Label|FileName"
oval_entries="
SLES 16|suse.linux.enterprise.server.16.xml.gz
SLES 15|suse.linux.enterprise.server.15.xml.gz
SLES 12|suse.linux.enterprise.server.12.xml.gz
SLES 11|suse.linux.enterprise.server.11.xml.gz
SLES 10|suse.linux.enterprise.server.10.xml.gz
Open SUSE 16.0|opensuse.leap.16.0.xml.gz
Open SUSE 15.6|opensuse.leap.15.6.xml.gz
Open SUSE 15.5|opensuse.leap.15.5.xml.gz
Open SUSE 15.4|opensuse.leap.15.4.xml.gz
Open SUSE 15.3|opensuse.leap.15.3.xml.gz
Open SUSE 15.2|opensuse.leap.15.2.xml.gz
Open SUSE 15.1|opensuse.leap.15.1.xml.gz
Open SUSE 15.0|opensuse.leap.15.0.xml.gz
SUSE Liberty 7|suse.liberty.linux.7.xml.gz
SUSE Liberty 7 Patch|suse.liberty.linux.7-patch.xml.gz
SUSE Liberty 8|suse.liberty.linux.8.xml.gz
SUSE Liberty 8 Patch|suse.liberty.linux.8-patch.xml.gz
SUSE Liberty 9|suse.liberty.linux.9.xml.gz
SUSE Liberty 9 Patch|suse.liberty.linux.9-patch.xml.gz
Open SUSE Tumbleweed|opensuse.tumbleweed.xml.gz
SLE Micro 5.0|suse.linux.enterprise.micro.5.0.xml.gz
SLE Micro 5.0 Patch|suse.linux.enterprise.micro.5.0-patch.xml.gz
SLE Micro 5.1|suse.linux.enterprise.micro.5.1.xml.gz
SLE Micro 5.1 Patch|suse.linux.enterprise.micro.5.1-patch.xml.gz
SLE Micro 5.2|suse.linux.enterprise.micro.5.2.xml.gz
SLE Micro 5.2 Patch|suse.linux.enterprise.micro.5.2-patch.xml.gz
SLE Micro 5.3|suse.linux.enterprise.micro.5.3.xml.gz
SLE Micro 5.3 Patch|suse.linux.enterprise.micro.5.3-patch.xml.gz
SLE Micro 5.4|suse.linux.enterprise.micro.5.4.xml.gz
SLE Micro 5.4 Patch|suse.linux.enterprise.micro.5.4-patch.xml.gz
SLE Micro 5.5|suse.linux.enterprise.micro.5.5.xml.gz
SLE Micro 5.5 Patch|suse.linux.enterprise.micro.5.5-patch.xml.gz
SLE Micro 5|suse.linux.enterprise.micro.5.xml.gz
SLE Micro 5 Patch|suse.linux.enterprise.micro.5-patch.xml.gz
SLE Micro 6.0|suse.linux.enterprise.micro.6.0.xml.gz
SLE Micro 6.0 Patch|suse.linux.enterprise.micro.6.0-patch.xml.gz
SLE Micro 6.1|suse.linux.enterprise.micro.6.1.xml.gz
SLE Micro 6.1 Patch|suse.linux.enterprise.micro.6.1-patch.xml.gz
"

echo "$oval_entries" | while IFS='|' read -r label file; do
  fetch_and_process_suse_oval "$label" "suse" "$file"
done


############## Amazon ###############

echo -e "\n*** Update: Amazon ***\n"
mkdir -p "$VUL_SOURCE_DIR/amazon"

download_and_publish_gzip "amazon 1" \
    "https://alas.aws.amazon.com/alas.rss" \
    "$VUL_SOURCE_DIR/amazon/alas.rss"
download_and_publish_gzip "amazon 2" \
    "https://alas.aws.amazon.com/AL2/alas.rss" \
    "$VUL_SOURCE_DIR/amazon/alas2.rss"
download_and_publish_gzip "amazon 2022" \
    "https://alas.aws.amazon.com/AL2022/alas.rss" \
    "$VUL_SOURCE_DIR/amazon/alas2022.rss"
download_and_publish_gzip "amazon 2023" \
    "https://alas.aws.amazon.com/AL2023/alas.rss" \
    "$VUL_SOURCE_DIR/amazon/alas2023.rss"


############## photon ###############

echo -e "\n*** Update: Photon ***\n"
mkdir -p "$VUL_SOURCE_DIR/photon"

base=https://packages.vmware.com/photon/photon_cve_metadata
file=photon_versions.json
curl $base/$file | jq -r .branches[] |  while read ver; do
	file=cve_data_photon${ver}.json
    download_and_publish_gzip "photon ${ver}" "$base/${file}" "$VUL_SOURCE_DIR/photon/${file}"
done

############## Red Hat ###############

echo -e "\n*** Update: Red Hat ***\n"

mkdir -p "$VUL_SOURCE_DIR/redhat/7"

rhel=rhel-7.oval.xml.bz2
download_and_publish_file "rhel-7" \
    "https://www.redhat.com/security/data/oval/v2/RHEL7/$rhel" \
    "$VUL_SOURCE_DIR/redhat/7/$rhel"

rhel=rhel-7-including-unpatched.oval.xml.bz2
download_and_publish_file "rhel-7-unpatch" \
    "https://www.redhat.com/security/data/oval/v2/RHEL7/$rhel" \
    "$VUL_SOURCE_DIR/redhat/7/$rhel"

rhel=rhsso.oval.xml.bz2
download_and_publish_file "rhsso-7" \
    "https://www.redhat.com/security/data/oval/v2/RHEL7/$rhel" \
    "$VUL_SOURCE_DIR/redhat/7/$rhel"

rhel=rhsso-including-unpatched.oval.xml.bz2
download_and_publish_file "rhsso-7-unpatch" \
    "https://www.redhat.com/security/data/oval/v2/RHEL7/$rhel" \
    "$VUL_SOURCE_DIR/redhat/7/$rhel"

mkdir -p "$VUL_SOURCE_DIR/redhat/8"

rhel=rhel-8.oval.xml.bz2
download_and_publish_file "rhel-8" \
    "https://www.redhat.com/security/data/oval/v2/RHEL8/$rhel" \
    "$VUL_SOURCE_DIR/redhat/8/$rhel"

rhel=rhel-8-including-unpatched.oval.xml.bz2
download_and_publish_file "rhel-8-unpatch" \
    "https://www.redhat.com/security/data/oval/v2/RHEL8/$rhel" \
    "$VUL_SOURCE_DIR/redhat/8/$rhel"

rhel=rhsso.oval.xml.bz2
download_and_publish_file "rhsso-8" \
    "https://www.redhat.com/security/data/oval/v2/RHEL8/$rhel" \
    "$VUL_SOURCE_DIR/redhat/8/$rhel"

rhel=rhsso-including-unpatched.oval.xml.bz2
download_and_publish_file "rhsso-8-unpatch" \
    "https://www.redhat.com/security/data/oval/v2/RHEL8/$rhel" \
    "$VUL_SOURCE_DIR/redhat/8/$rhel"

rhel=fast-datapath.oval.xml.bz2
download_and_publish_file "fastdp-8" \
    "https://www.redhat.com/security/data/oval/v2/RHEL8/$rhel" \
    "$VUL_SOURCE_DIR/redhat/8/$rhel"

rhel=fast-datapath-including-unpatched.oval.xml.bz2
download_and_publish_file "fastdp-8-unpatch" \
    "https://www.redhat.com/security/data/oval/v2/RHEL8/$rhel" \
    "$VUL_SOURCE_DIR/redhat/8/$rhel"

for minor in {1..30}; do
    rhel=openshift-4.$minor.oval.xml.bz2
    tmp=$(prepare_temp_file "$VUL_SOURCE_DIR/redhat/8/$rhel")
    curl -fk -o "$tmp" "https://www.redhat.com/security/data/oval/v2/RHEL8/$rhel"
    if [ $? -eq 0 ]; then
        publish_file "oc-4.$minor" "$tmp" "$VUL_SOURCE_DIR/redhat/8/$rhel"
    else
        rm -f "$tmp"
    fi
done

rhel=openshift-4-including-unpatched.oval.xml.bz2
download_and_publish_file "oc-4.unpatch" \
    "https://www.redhat.com/security/data/oval/v2/RHEL8/$rhel" \
    "$VUL_SOURCE_DIR/redhat/8/$rhel"


mkdir -p "$VUL_SOURCE_DIR/redhat/9"

rhel=rhel-9.oval.xml.bz2
download_and_publish_file "rhel-9" \
    "https://www.redhat.com/security/data/oval/v2/RHEL9/$rhel" \
    "$VUL_SOURCE_DIR/redhat/9/$rhel"

rhel=rhel-9-including-unpatched.oval.xml.bz2
download_and_publish_file "rhel-9-unpatch" \
    "https://www.redhat.com/security/data/oval/v2/RHEL9/$rhel" \
    "$VUL_SOURCE_DIR/redhat/9/$rhel"

rhel=rhsso.oval.xml.bz2
download_and_publish_file "rhsso-9" \
    "https://www.redhat.com/security/data/oval/v2/RHEL9/$rhel" \
    "$VUL_SOURCE_DIR/redhat/9/$rhel"

rhel=rhsso-including-unpatched.oval.xml.bz2
download_and_publish_file "rhsso-9-unpatch" \
    "https://www.redhat.com/security/data/oval/v2/RHEL9/$rhel" \
    "$VUL_SOURCE_DIR/redhat/9/$rhel"

rhel=fast-datapath.oval.xml.bz2
download_and_publish_file "fastdp-9" \
    "https://www.redhat.com/security/data/oval/v2/RHEL9/$rhel" \
    "$VUL_SOURCE_DIR/redhat/9/$rhel"

rhel=fast-datapath-including-unpatched.oval.xml.bz2
download_and_publish_file "fastdp-9-unpatch" \
    "https://www.redhat.com/security/data/oval/v2/RHEL9/$rhel" \
    "$VUL_SOURCE_DIR/redhat/9/$rhel"

for minor in {12..30}; do
    rhel=openshift-4.$minor.oval.xml.bz2
    tmp=$(prepare_temp_file "$VUL_SOURCE_DIR/redhat/9/$rhel")
    curl -fk -o "$tmp" "https://www.redhat.com/security/data/oval/v2/RHEL9/$rhel"
    if [ $? -eq 0 ]; then
        publish_file "oc-4.$minor" "$tmp" "$VUL_SOURCE_DIR/redhat/9/$rhel"
    else
        rm -f "$tmp"
    fi
done

rhel=openshift-4-including-unpatched.oval.xml.bz2
download_and_publish_file "oc-4.unpatch" \
    "https://www.redhat.com/security/data/oval/v2/RHEL9/$rhel" \
    "$VUL_SOURCE_DIR/redhat/9/$rhel"



############## apps ###############

echo -e "\n*** Update: apps ***\n"
mkdir -p "$VUL_SOURCE_DIR/apps"
download_and_publish_gzip "k8s" \
    "https://k8s.io/docs/reference/issues-security/official-cve-feed/index.json" \
    "$VUL_SOURCE_DIR/apps/k8s.json"

echo -e "\n****** Download go OSV advisories"
download_golang_osv_data "$VUL_SOURCE_DIR/apps/golang-osv.zip"

################## chainguard  ####################

echo -e "\n****** Download chainguard OSV advisories"
mkdir -p "$VUL_SOURCE_DIR/chainguard"
download_chainguard_osv_v2_data "$VUL_SOURCE_DIR/chainguard/osv-v2.zip"
############## github security advisory ###############

echo -e "\n*** Update: github security advisory ***\n"
mkdir -p "$VUL_SOURCE_DIR/github"

tmp=$(prepare_temp_file "$VUL_SOURCE_DIR/github/npm.data")
if download_ghsa "NPM" "$tmp"; then
    gzip -f "$tmp"
    publish_file "NPM" "$tmp.gz" "$VUL_SOURCE_DIR/github/npm.data.gz"
else
    rm -f "$tmp" "$tmp.gz"
fi

tmp=$(prepare_temp_file "$VUL_SOURCE_DIR/github/maven.data")
if download_ghsa "MAVEN" "$tmp"; then
    gzip -f "$tmp"
    publish_file "MAVEN" "$tmp.gz" "$VUL_SOURCE_DIR/github/maven.data.gz"
else
    rm -f "$tmp" "$tmp.gz"
fi

tmp=$(prepare_temp_file "$VUL_SOURCE_DIR/github/go.data")
if download_ghsa "GO" "$tmp"; then
    gzip -f "$tmp"
    publish_file "GO" "$tmp.gz" "$VUL_SOURCE_DIR/github/go.data.gz"
else
    rm -f "$tmp" "$tmp.gz"
fi

tmp=$(prepare_temp_file "$VUL_SOURCE_DIR/github/pip.data")
if download_ghsa "PIP" "$tmp"; then
    gzip -f "$tmp"
    publish_file "PIP" "$tmp.gz" "$VUL_SOURCE_DIR/github/pip.data.gz"
else
    rm -f "$tmp" "$tmp.gz"
fi

tmp=$(prepare_temp_file "$VUL_SOURCE_DIR/github/nuget.data")
if download_ghsa "NUGET" "$tmp"; then
    gzip -f "$tmp"
    publish_file "NUGET" "$tmp.gz" "$VUL_SOURCE_DIR/github/nuget.data.gz"
else
    rm -f "$tmp" "$tmp.gz"
fi

tmp=$(prepare_temp_file "$VUL_SOURCE_DIR/github/php.data")
if download_ghsa "COMPOSER" "$tmp"; then
    gzip -f "$tmp"
    publish_file "COMPOSER" "$tmp.gz" "$VUL_SOURCE_DIR/github/php.data.gz"
else
    rm -f "$tmp" "$tmp.gz"
fi

# nvd

BASE_URL="${BASE_URL:-https://nvd.nist.gov/feeds/json/cve/2.0}"
START_YEAR="${START_YEAR:-2002}"
END_YEAR="${END_YEAR:-2026}"
FEED_DIR="${FEED_DIR:-$VUL_SOURCE_DIR/feeds}"
OUTPUT_FILE="${OUTPUT_FILE:-$VUL_SOURCE_DIR/merged_nvd_feeds.json.gz}"
TEMP_DIR=$(mktemp -d)
VULNS_FILE="$TEMP_DIR/all_vulns.jsonl"

log() {
  echo "[update-nvd-feeds] $*"
}

write_output() {
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "$1=$2" >> "$GITHUB_OUTPUT"
  fi
}

download_nvd_feed() {
  local year="$1"
  local file="nvdcve-2.0-${year}.json.gz"
  local url="${BASE_URL}/${file}"
  local out="${FEED_DIR}/${file}"
  local wget_args=(-O "$out" "$url")

  if [ -n "${NVD_KEY:-}" ]; then
    wget_args=(--header="apiKey: ${NVD_KEY}" "${wget_args[@]}")
  fi

  log "Downloading file=$file year=$year"
  if wget "${wget_args[@]}"; then
    if [ -s "$out" ]; then
      local size
      size=$(du -h "$out" | awk '{print $1}')
      log "DOWNLOAD_OK file=$file size=$size"
      return 0
    fi
  fi

  log "DOWNLOAD_FAILED file=$file"
  rm -f "$out"
  return 1
}

merge_nvd_feeds() {
  local file_count
  file_count=$(find "$FEED_DIR" -name "nvdcve-2.0-*.json.gz" | wc -l | tr -d ' ')
  log "FILE_COUNT=$file_count"

  if [ "$file_count" -eq 0 ]; then
    log "No NVD feed files found. Nothing to merge."
    exit 1
  fi

  log "Extracting vulnerabilities"
  local counter=0
  while IFS= read -r file; do
    counter=$((counter + 1))
    local file_name year
    file_name=$(basename "$file")
    year=$(echo "$file_name" | sed -E 's/.*-([0-9]{4})\.json\.gz/\1/')
    log "PROCESSING_FILE index=$counter total=$file_count year=$year file=$file_name"
    gzip -cd "$file" | jq -c '.vulnerabilities[]' >> "$VULNS_FILE"
    local current_total
    current_total=$(wc -l < "$VULNS_FILE" | tr -d ' ')
    log "PROGRESS files_processed=$counter vulnerabilities=$current_total"
  done < <(find "$FEED_DIR" -name "nvdcve-2.0-*.json.gz" | sort -V)

  log "Building merged JSON"
  local first_file format version timestamp
  first_file=$(find "$FEED_DIR" -name "nvdcve-2.0-*.json.gz" | sort -V | head -1)
  local meta
  meta=$(gzip -cd "$first_file")
  format=$(echo "$meta" | jq -r '.format')
  version=$(echo "$meta" | jq -r '.version')
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.%3N")
  local total_vulns
  total_vulns=$(wc -l < "$VULNS_FILE" | tr -d ' ')
  log "TOTAL_VULNERABILITIES=$total_vulns"

  {
    echo "{"
    echo "  \"resultsPerPage\": $total_vulns,"
    echo "  \"startIndex\": 0,"
    echo "  \"totalResults\": $total_vulns,"
    echo "  \"format\": \"$format\","
    echo "  \"version\": \"$version\","
    echo "  \"timestamp\": \"$timestamp\","
    echo "  \"vulnerabilities\": ["
    awk '{
      if (NR > 1) print ","
      printf "%s", $0
    }' "$VULNS_FILE"
    echo ""
    echo "  ]"
    echo "}"
  } | gzip > "$OUTPUT_FILE"
}

clean_up() {
  rm -rf "$TEMP_DIR"
}

log "Starting NVD feeds update"
log "START_YEAR=$START_YEAR"
log "END_YEAR=$END_YEAR"
log "FEED_DIR=$FEED_DIR"
log "OUTPUT_FILE=$OUTPUT_FILE"

mkdir -p "$FEED_DIR"

for year in $(seq "$START_YEAR" "$END_YEAR"); do
  download_nvd_feed "$year"
done

# merge_nvd_feeds

# TOTAL_VULNS=$(gzip -cd "$OUTPUT_FILE" | jq '.totalResults')
# OUTPUT_SIZE=$(du -h "$OUTPUT_FILE" | awk '{print $1}')

# write_output "output_file" "$OUTPUT_FILE"
# write_output "total_vulnerabilities" "$TOTAL_VULNS"
# write_output "output_size" "$OUTPUT_SIZE"
# log "OUTPUT_FILE=$OUTPUT_FILE"
# log "OUTPUT_SIZE=$OUTPUT_SIZE"
# log "Update complete"

echo -e "\n******************* update done *******************\n"

exit 0
