echo -e "\n******************* update start *******************\n"

mkdir -p stage
rm -f stage/*

############## NVD 2.0 ###############

echo -e "\n*** Update: NVD ***\n"

start=0
retry=0
while true
do
    url="https://services.nvd.nist.gov/rest/json/cves/2.0?startIndex=$start"
    file="stage/$start.json"

    echo "downloading $file ..."
    wget -q --no-check-certificate -O $file --header="apiKey: $NVD_KEY" $url
    if [ $? -ne 0 ]; then
        retry=$((retry+1))
        if [[ $retry -eq 10 ]]; then
            echo "Failed to download nvd 2.0"
            break
        fi
        sleep 10
    else
        count=$(jq .resultsPerPage $file)
        if [ $? -ne 0 ]; then
            retry=$((retry+1))
        elif [[ $count -gt 0 ]]; then
			gzip $file
            retry=0
            start=$((start+count))
        else
			gzip $file
            retry=0

            echo -e "\n*** commit NVD changes ***\n"
            mkdir -p nvd
            rm -f nvd/*
            mv stage/* nvd/
            git add nvd
            git commit -m "update nvd" || { echo "Failed to commit nvd"; }
            echo "done!"
            break
        fi
    fi

    if [[ $retry -eq 0 ]]; then
        sleep 5
    elif [[ $retry -lt 10 ]]; then
        sleep 10
    else
        echo "Failed to download"
        break
    fi
done

echo -e "\n******************* update done *******************\n"


exit 0
