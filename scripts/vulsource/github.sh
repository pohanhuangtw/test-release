#!/usr/bin/env bash
# Legacy references:
# - scripts/jenkins-ssh-script-vulsource.sh, function download_ghsa()
# - scripts/jenkins-ssh-script-vulsource.sh, section "Update: github security advisory"
# Upstream references:
# - https://api.github.com/graphql
# - https://docs.github.com/en/graphql/reference/queries#securityvulnerabilities
set -uo pipefail
source "$(dirname "$0")/_lib.sh"
ghsaBatch=80
ghsaToken="${GITHUB_TOKEN:-}"

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
        echo ${ghsaQuery/GHSACURSOR/$nextCursor} > "${STAGE_DIR}/ghsa.query"

        output=$(curl -s -X POST --data "@${STAGE_DIR}/ghsa.query" -H "Authorization: bearer $ghsaToken"  https://api.github.com/graphql)
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

FEED="github"
dir=$(begin_output "$FEED")

download_ghsa "NPM" "$dir/npm.data" result
download_ghsa "MAVEN" "$dir/maven.data" result
download_ghsa "GO" "$dir/go.data" result
download_ghsa "PIP" "$dir/pip.data" result
download_ghsa "NUGET" "$dir/nuget.data" result
download_ghsa "COMPOSER" "$dir/php.data" result

# Compress all .data files
for datafile in "$dir"/*.data; do
    if [ -f "$datafile" ]; then
        gzip "$datafile"
        echo "Compressed: $(basename "$datafile").gz"
    fi
done

verify_no_empty_files "$dir"
verify_manifest "$FIXTURES_ROOT/$FEED" "$dir"
finish_output "$FEED" 
