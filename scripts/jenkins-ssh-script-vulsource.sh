ghsaBatch=80
ghsaToken="${GHSA_TOKEN:-${GH_TOKEN:-${GITHUB_TOKEN:-}}}"

if [ -z "$ghsaToken" ]; then
    echo "GHSA_TOKEN, GH_TOKEN, or GITHUB_TOKEN is required for GitHub advisory downloads" >&2
    exit 1
fi

download_ghsa() {
    local module=$1
    local datafile=$2
    local __result=$3

    read -d '' ghsaQuery << EOM
{
  "query": "query {
    securityVulnerabilities(orderBy: {field: UPDATED_AT, direction: ASC}, ecosystem: $module, first: $ghsaBatch GHSACURSOR) {
      totalCount
      nodes {
        advisory {
          ghsaId
          severity
          publishedAt
          updatedAt
          permalink
          identifiers {
            type
            value
          }
          cwes(first: 5) {
            nodes {
              cweId
            }
          }
          cvss {
            score
            vectorString
          }
          summary
          description
          references {
            url
          }
        }
        firstPatchedVersion {
          identifier
        }
        vulnerableVersionRange
        package {
          ecosystem
          name
        }
      }
      pageInfo {
        endCursor
        hasNextPage
      }
    }
  }"
}
EOM

    local hasNextPage=true
    local nextCursor=

    rm -f $datafile
    echo -e "\n\n****** Download $module advisories"

    while [ "$hasNextPage" == "true" ]; do
        echo ${ghsaQuery/GHSACURSOR/$nextCursor} > ghsa.query

        output=$(curl -s -X POST --data "@ghsa.query" -H "Authorization: bearer $ghsaToken"  https://api.github.com/graphql)
        if [ $? -ne 0 ]; then
            echo "Failed to send the request: $?"
            break
        fi

        hasNextPage=$(jq -c -r '.data.securityVulnerabilities.pageInfo.hasNextPage' <<< $output)
        endCursor=$(jq -c -r '.data.securityVulnerabilities.pageInfo.endCursor' <<< $output)

        if [ "$hasNextPage" == "null" ]; then
            echo "Failed to parse the result:"
            echo $output
            break
        fi

        # Append data to file
        jq -c -r '.data.securityVulnerabilities.nodes[]' <<< $output >> $datafile
        if [ $? -ne 0 ]; then
            echo "Failed to write to $datafile: $?"
            break
        fi

        if [ "$hasNextPage" == "true" ]; then
            nextCursor=", after: \\\"$endCursor\\\""
        fi

        echo ${#output} $hasNextPage $endCursor $(wc -l < $datafile)
    done

    if [ "$hasNextPage" == "false" ]; then
        eval $__result=0
    else
        eval $__result=1
    fi
}

download_golang_osv_data() {
    local outputfile="stage/golang-osv.zip"
    local osv_repo_url="https://github.com/golang/vulndb.git"
    local clone_dir="stage/vulndb-osv"

    mkdir -p stage
    rm -rf "$clone_dir"

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

    local abs_output="$(pwd)/$outputfile"
    (cd "$clone_dir/data/osv" && zip -r "$abs_output" *.json)

    if [ $? -ne 0 ] || [ ! -s "$outputfile" ]; then
        echo "Failed to create archive"
        rm -rf "$clone_dir"
        return 1
    fi

    echo "Successfully created $(du -h "$outputfile" | cut -f1) archive"
    rm -rf "$clone_dir"
    return 0
}

download_chainguard_osv_v2_data() {
  local outputfile="stage/osv-v2.zip"
  local index_url="https://advisories.cgr.dev/chainguard/v2/osv/all.json"
  local advisory_base_url="https://advisories.cgr.dev/chainguard/v2/osv"
  local download_dir="stage/chainguard-v2-osv"
  local retries=5
  local retry_delay=5
  local connect_timeout=10

  mkdir -p stage
  rm -rf "$download_dir"
  mkdir -p "$download_dir"

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
  while read -r id; do
    count=$((count + 1))
    url="${advisory_base_url}/${id}.json"
    out="${download_dir}/${id}.json"
    if curl -fsSL --connect-timeout "$connect_timeout" --retry "$retries" --retry-delay "$retry_delay" -o "$out" "$url"; then
      printf "\r[%d/%d] %s" "$count" "$total" "$id"
    else
      failed=$((failed + 1))
      printf "\n[%d/%d] FAILED: %s\n" "$count" "$total" "$id" >&2
    fi
  done < "$ids_file"
  echo ""

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
  abs_output="$(cd "$(dirname "$outputfile")" && pwd)/$(basename "$outputfile")"
  (cd "$download_dir" && zip -r -q "$abs_output" *.json)
  if [ $? -ne 0 ] || [ ! -s "$outputfile" ]; then
    echo "Failed to create archive"
    rm -rf "$download_dir"
    return 1
  fi

  echo "Successfully created $(du -h "$outputfile" | cut -f1) archive ($file_count advisories)"
  rm -rf "$download_dir"
  return 0
}

compare_and_commmit()
{
    SOURCE=$1
    FOLDER=$2
    FILE=$3

    if [ -s stage/$FILE ]; then
        if [[ "$FILE" == *.bz2 ]] || [[ "$FILE" == *.gz ]] || [[ "$FILE" == *.zip ]]; then
            OLDFILE=$FOLDER/$FILE
            NEWFILE=stage/$FILE
        else
            gzip stage/$FILE
            if [ $? -ne 0 ]; then
                echo "Failed to gzip stage/$FILE"
                return
            fi

            OLDFILE=$FOLDER/$FILE.gz
            NEWFILE=stage/$FILE.gz
        fi

        # Ensure the new added file can be committed
        mkdir -p "$FOLDER"
        test -f $OLDFILE || touch $OLDFILE

        OLDVER=$(md5sum $OLDFILE | awk '{print $1}')
        NEWVER=$(md5sum $NEWFILE | awk '{print $1}')

        echo -e "\n*** old version=$OLDVER ***"
        echo -e "*** new version=$NEWVER ***\n"
        if [[ "$NEWVER" != "$OLDVER" ]]; then
            echo -e "\n*** commit $SOURCE changes ***\n"
            mv $NEWFILE $OLDFILE
            git add $OLDFILE
            git commit -m "update $OLDFILE" || { echo "Failed to commit $OLDFILE"; }
            if [ $? -ne 0 ]; then
                echo "Failed to commit $OLDFILE"
                git reset HEAD -- .
            fi
        fi
    fi
}

push_and_cleanup() {
  local section=$1
  echo -e "\n*** push $section updates ***\n"
  git push origin main || { echo "Failed to push $section updates"; }
  rm -rf stage
  mkdir -p stage
}

fetch_and_process_suse_oval() {
    local source=$1
    local folder=$2
    local file=$3

    local url="https://ftp.suse.com/pub/projects/security/oval/$file"
    local dest="stage/$file"

    if wget --no-check-certificate -O "$dest" "$url"; then
        if gzip -t "$dest" ; then
            compare_and_commmit "$source" "$folder" "$file"
            echo "Downloaded $file successfully"
        else
            echo "Server returned $status - feed not available: $url"
            return 1
        fi
    else
        echo "Failed to download $file from $url"
        return 1
    fi
}

echo -e "\n******************* update start *******************\n"

mkdir -p stage

############## Ubuntu ###############

echo -e "\n*** Update: ubuntu ***\n"
git clone --depth 1 git://git.launchpad.net/ubuntu-cve-tracker stage/ubuntu-cve-tracker/
if [ $? -eq 0 ]; then
    OLDVER=$(cat ubuntu-cve-tracker.commit)
    cd stage/ubuntu-cve-tracker
    NEWVER=$(git rev-parse HEAD)
    cd ../..
    echo -e "\n*** old version=$OLDVER ***"
    echo -e "*** new version=$NEWVER ***\n"
    if [[ "$NEWVER" != "$OLDVER" ]]; then
        echo -e "\n*** commit ubuntu changes ***\n"
        mv ubuntu-cve-tracker stage/ubuntu-cve-tracker.old
        mv stage/ubuntu-cve-tracker .
        rm -rf ubuntu-cve-tracker/.git
        echo $NEWVER > ubuntu-cve-tracker.commit
        git add -A ubuntu-cve-tracker
        git add ubuntu-cve-tracker.commit
        git commit -m "update ubuntu-cve-tracker"
        if [ $? -ne 0 ]; then
            echo "Failed to commit ubuntu-cve-tracker"
            git reset HEAD -- .
        fi
    fi
fi

push_and_cleanup "ubuntu"

############## Mariner ###############

echo -e "\n*** Update: mariner ***\n"
git clone --depth 1 https://github.com/microsoft/CBL-MarinerVulnerabilityData stage/mariner-vulnerability/
if [ $? -eq 0 ]; then
    OLDVER=$(cat mariner-vulnerability.commit)
    cd stage/mariner-vulnerability
    NEWVER=$(git rev-parse HEAD)
    cd ../..
    echo -e "\n*** old version=$OLDVER ***"
    echo -e "*** new version=$NEWVER ***\n"
    if [[ "$NEWVER" != "$OLDVER" ]]; then
        echo -e "\n*** commit mariner changes ***\n"
        mv mariner-vulnerability stage/mariner-vulnerability.old
        mv stage/mariner-vulnerability .
        rm -rf mariner-vulnerability/.git
        echo $NEWVER > mariner-vulnerability.commit
        git add -A mariner-vulnerability
        git add mariner-vulnerability.commit
        git commit -m "update mariner-vulnerability"
        if [ $? -ne 0 ]; then
            echo "Failed to commit mariner-vulnerability"
            git reset HEAD -- .
        fi
    fi
fi

push_and_cleanup "mariner"

############## Debian ###############

echo -e "\n*** Update: debian ***\n"
mkdir -p debian

OLDVER=$(md5sum debian/debian.json | awk '{print $1}')
wget --no-check-certificate -O stage/debian.json https://security-tracker.debian.org/tracker/data/json
if [ -s stage/debian.json ]; then
    NEWVER=$(md5sum stage/debian.json | awk '{print $1}')
    echo -e "\n*** old version=$OLDVER ***"
    echo -e "*** new version=$NEWVER ***\n"
    if [[ "$NEWVER" != "$OLDVER" ]]; then
        echo -e "\n*** commit debian changes ***\n"
        mv stage/debian.json debian/debian.json
        git add debian/debian.json
        git commit -m "update debian.json" || { echo "Failed to commit debian.json"; }
        if [ $? -ne 0 ]; then
            echo "Failed to commit debian"
            git reset HEAD -- .
        fi
    fi
fi

push_and_cleanup "debian"

############## SUSE ###############

echo -e "\n*** Update: SUSE ***\n"
mkdir -p suse

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

push_and_cleanup "suse"

############## Amazon ###############

echo -e "\n*** Update: Amazon ***\n"
mkdir -p amazon

wget --no-check-certificate -O stage/alas.rss https://alas.aws.amazon.com/alas.rss
compare_and_commmit "amazon 1" "amazon" "alas.rss"

wget --no-check-certificate -O stage/alas2.rss https://alas.aws.amazon.com/AL2/alas.rss
compare_and_commmit "amazon 2" "amazon" "alas2.rss"

wget --no-check-certificate -O stage/alas2022.rss https://alas.aws.amazon.com/AL2022/alas.rss
compare_and_commmit "amazon 2022" "amazon" "alas2022.rss"

wget --no-check-certificate -O stage/alas2023.rss https://alas.aws.amazon.com/AL2023/alas.rss
compare_and_commmit "amazon 2023" "amazon" "alas2023.rss"

push_and_cleanup "amazon"

############## photon ###############

echo -e "\n*** Update: Photon ***\n"
mkdir -p photon

base=https://packages.vmware.com/photon/photon_cve_metadata
file=photon_versions.json
curl $base/$file | jq -r .branches[] |  while read ver; do
	file=cve_data_photon${ver}.json
    wget --no-check-certificate -O stage/${file} $base/${file}
    compare_and_commmit "photon ${VER}" "photon" ${file}
done

push_and_cleanup "photon"

############## Red Hat ###############

echo -e "\n*** Update: Red Hat ***\n"

mkdir -p redhat/7
mkdir -p stage/7

rhel=rhel-7.oval.xml.bz2
wget --no-check-certificate -O stage/7/$rhel https://www.redhat.com/security/data/oval/v2/RHEL7/$rhel
compare_and_commmit "rhel-7" "redhat" "7/$rhel"

rhel=rhel-7-including-unpatched.oval.xml.bz2
wget --no-check-certificate -O stage/7/$rhel https://www.redhat.com/security/data/oval/v2/RHEL7/$rhel
compare_and_commmit "rhel-7-unpatch" "redhat" "7/$rhel"

rhel=rhsso.oval.xml.bz2
wget --no-check-certificate -O stage/7/$rhel https://www.redhat.com/security/data/oval/v2/RHEL7/$rhel
compare_and_commmit "rhsso-7" "redhat" "7/$rhel"

rhel=rhsso-including-unpatched.oval.xml.bz2
wget --no-check-certificate -O stage/7/$rhel https://www.redhat.com/security/data/oval/v2/RHEL7/$rhel
compare_and_commmit "rhsso-7-unpatch" "redhat" "7/$rhel"

mkdir -p redhat/8
mkdir -p stage/8

rhel=rhel-8.oval.xml.bz2
wget --no-check-certificate -O stage/8/$rhel https://www.redhat.com/security/data/oval/v2/RHEL8/$rhel
compare_and_commmit "rhel-8" "redhat" "8/$rhel"

rhel=rhel-8-including-unpatched.oval.xml.bz2
wget --no-check-certificate -O stage/8/$rhel https://www.redhat.com/security/data/oval/v2/RHEL8/$rhel
compare_and_commmit "rhel-8-unpatch" "redhat" "8/$rhel"

rhel=rhsso.oval.xml.bz2
wget --no-check-certificate -O stage/8/$rhel https://www.redhat.com/security/data/oval/v2/RHEL8/$rhel
compare_and_commmit "rhsso-8" "redhat" "8/$rhel"

rhel=rhsso-including-unpatched.oval.xml.bz2
wget --no-check-certificate -O stage/8/$rhel https://www.redhat.com/security/data/oval/v2/RHEL8/$rhel
compare_and_commmit "rhsso-8-unpatch" "redhat" "8/$rhel"

rhel=fast-datapath.oval.xml.bz2
wget --no-check-certificate -O stage/8/$rhel https://www.redhat.com/security/data/oval/v2/RHEL8/$rhel
compare_and_commmit "fastdp-8" "redhat" "8/$rhel"

rhel=fast-datapath-including-unpatched.oval.xml.bz2
wget --no-check-certificate -O stage/8/$rhel https://www.redhat.com/security/data/oval/v2/RHEL8/$rhel
compare_and_commmit "fastdp-8-unpatch" "redhat" "8/$rhel"

for minor in {1..30}; do
    rhel=openshift-4.$minor.oval.xml.bz2
    curl -fk -o stage/8/$rhel https://www.redhat.com/security/data/oval/v2/RHEL8/$rhel
    if [ $? -eq 0 ]; then
        compare_and_commmit "oc-4.$minor" "redhat" "8/$rhel"
    fi
done

rhel=openshift-4-including-unpatched.oval.xml.bz2
wget --no-check-certificate -O stage/8/$rhel https://www.redhat.com/security/data/oval/v2/RHEL8/$rhel
compare_and_commmit "oc-4.unpatch" "redhat" "8/$rhel"


mkdir -p redhat/9
mkdir -p stage/9

rhel=rhel-9.oval.xml.bz2
wget --no-check-certificate -O stage/9/$rhel https://www.redhat.com/security/data/oval/v2/RHEL9/$rhel
compare_and_commmit "rhel-9" "redhat" "9/$rhel"

rhel=rhel-9-including-unpatched.oval.xml.bz2
wget --no-check-certificate -O stage/9/$rhel https://www.redhat.com/security/data/oval/v2/RHEL9/$rhel
compare_and_commmit "rhel-9-unpatch" "redhat" "9/$rhel"

rhel=rhsso.oval.xml.bz2
wget --no-check-certificate -O stage/9/$rhel https://www.redhat.com/security/data/oval/v2/RHEL9/$rhel
compare_and_commmit "rhsso-9" "redhat" "9/$rhel"

rhel=rhsso-including-unpatched.oval.xml.bz2
wget --no-check-certificate -O stage/9/$rhel https://www.redhat.com/security/data/oval/v2/RHEL9/$rhel
compare_and_commmit "rhsso-9-unpatch" "redhat" "9/$rhel"

rhel=fast-datapath.oval.xml.bz2
wget --no-check-certificate -O stage/9/$rhel https://www.redhat.com/security/data/oval/v2/RHEL9/$rhel
compare_and_commmit "fastdp-9" "redhat" "9/$rhel"

rhel=fast-datapath-including-unpatched.oval.xml.bz2
wget --no-check-certificate -O stage/9/$rhel https://www.redhat.com/security/data/oval/v2/RHEL9/$rhel
compare_and_commmit "fastdp-9-unpatch" "redhat" "9/$rhel"

for minor in {12..30}; do
    rhel=openshift-4.$minor.oval.xml.bz2
    curl -fk -o stage/9/$rhel https://www.redhat.com/security/data/oval/v2/RHEL9/$rhel
    if [ $? -eq 0 ]; then
        compare_and_commmit "oc-4.$minor" "redhat" "9/$rhel"
    fi
done

rhel=openshift-4-including-unpatched.oval.xml.bz2
wget --no-check-certificate -O stage/9/$rhel https://www.redhat.com/security/data/oval/v2/RHEL9/$rhel
compare_and_commmit "oc-4.unpatch" "redhat" "9/$rhel"

push_and_cleanup "redhat"

############## apps ###############

echo -e "\n*** Update: apps ***\n"
mkdir -p apps

wget --no-check-certificate -O stage/k8s.json https://k8s.io/docs/reference/issues-security/official-cve-feed/index.json
compare_and_commmit "k8s" "apps" "k8s.json"

echo -e "\n****** Download go OSV advisories"
download_golang_osv_data
if [[ $? -eq 0 ]]; then
    compare_and_commmit "golang_osv" "apps" "golang-osv.zip"
fi

push_and_cleanup "apps"

################## chainguard  ####################

echo -e "\n****** Download chainguard OSV advisories"
mkdir -p chainguard

download_chainguard_osv_v2_data
if [[ $? -eq 0 ]]; then
  compare_and_commmit "osv-v2" "chainguard" "osv-v2.zip"
fi

push_and_cleanup "chainguard"

############## github security advisory ###############

echo -e "\n*** Update: github security advisory ***\n"
mkdir -p github

download_ghsa "NPM" "stage/npm.data" result
if [ $result -eq 0 ]; then
    compare_and_commmit "NPM" "github" "npm.data"
fi

download_ghsa "MAVEN" "stage/maven.data" result
if [ $result -eq 0 ]; then
    compare_and_commmit "MAVEN" "github" "maven.data"
fi

download_ghsa "GO" "stage/go.data" result
if [ $result -eq 0 ]; then
    compare_and_commmit "GO" "github" "go.data"
fi

download_ghsa "PIP" "stage/pip.data" result
if [ $result -eq 0 ]; then
    compare_and_commmit "PIP" "github" "pip.data"
fi

download_ghsa "NUGET" "stage/nuget.data" result
if [ $result -eq 0 ]; then
    compare_and_commmit "NUGET" "github" "nuget.data"
fi

download_ghsa "NUGET" "stage/php.data" result
if [ $result -eq 0 ]; then
    compare_and_commmit "COMPOSER" "github" "php.data"
fi

push_and_cleanup "ghsa"

############## nvd ###############
BASE_URL="${BASE_URL:-https://nvd.nist.gov/feeds/json/cve/2.0}"
START_YEAR="${START_YEAR:-2002}"
END_YEAR="${END_YEAR:-2026}"

log() {
  echo "[nvd] $*"
}

mkdir -p nvd

if [ -f nvd/nvd.json.gz ]; then
  echo -e "\n*** remove legacy merged nvd.json.gz ***\n"
  git rm -f nvd/nvd.json.gz
  git commit -m "remove nvd/nvd.json.gz" || { echo "Failed to remove nvd/nvd.json.gz"; }
fi

log "Downloading NVD feeds from $START_YEAR to $END_YEAR"
file_count=0

for year in $(seq "$START_YEAR" "$END_YEAR"); do
  file="nvdcve-2.0-${year}.json.gz"
  url="${BASE_URL}/${file}"
  out="stage/$file"

  wget_args=(-O "$out" "$url")
  if [ -n "${NVD_KEY:-}" ]; then
    wget_args=(--header="apiKey: ${NVD_KEY}" "${wget_args[@]}")
  fi

  log "Downloading $file"
  if wget "${wget_args[@]}" 2>/dev/null && [ -s "$out" ]; then
    log "OK $file ($(du -h "$out" | awk '{print $1}'))"
    file_count=$((file_count + 1))
    compare_and_commmit "nvd ${year}" "nvd" "$file"
  else
    log "FAILED $file"
    rm -f "$out"
  fi
done

log "Downloaded $file_count feed files"

if [ "$file_count" -eq 0 ]; then
  log "No feeds downloaded, exiting"
  exit 1
fi

push_and_cleanup "nvd"

echo -e "\n******************* update done *******************\n"

exit 0
