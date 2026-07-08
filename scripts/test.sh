    set -euo pipefail

    rm -rf vul-dbgen/vul-source stage/vulndb-osv
    mkdir -p vul-dbgen/vul-source/apps stage

    git clone --depth 1 --filter=blob:none --sparse \
      https://github.com/golang/vulndb.git stage/vulndb-osv
    git -C stage/vulndb-osv sparse-checkout init --cone
    git -C stage/vulndb-osv sparse-checkout set data/osv

    (
      cd stage/vulndb-osv/data/osv
      tar czf "$GITHUB_WORKSPACE/vul-dbgen/vul-source/apps/golang-osv.tar.gz" *.json
    )

    rm -rf stage/vulndb-osv