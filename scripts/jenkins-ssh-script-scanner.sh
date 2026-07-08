############################### jenkins ssh command ################################
#
# echo -e "\n*** clone build ***\n"
# rm -rf release
# git clone git@github.com:neuvector/release.git || { echo "Failed to clone release repo"; exit 1; }
#
# echo -e "\n*** clean up jenkins-$JOB_NAME* ***\n"
# sudo -S rm -rf jenkins-$JOB_NAME*
#
# release/scripts/jenkins-ssh-script-scanner master $JOB_NAME $BUILD_TAG $BUILD_NUMBER
#
# exit 0
#


NV_BUILD_BRANCH=$1
JENKINS_JOB_NAME=$2
JENKINS_BUILD_TAG=$3
JENKINS_BUILD_NUMBER=$4
NV_TAG_AS=$5
NV_REL_AS=$6

echo -e "\n******************* Scanner $NV_BUILD_BRANCH Build Start *******************\n"

TO_BUILD_BRANCH=true

if [ "$TO_BUILD_BRANCH" = true ]; then
	NV_CONTAINER_TAG=$JENKINS_BUILD_TAG
else
	# Remove first 'v'
	NV_CONTAINER_TAG=${NV_BUILD_BRANCH#v}
fi

VULN_MAJOR_VER=1
VULN_MINOR_VER=$JENKINS_BUILD_NUMBER
until [ $VULN_MINOR_VER -lt 1000 ]; do
   let "VULN_MINOR_VER-=1000"
   let "VULN_MAJOR_VER++"
done
VULN_VER=`printf "%d.%03d" $VULN_MAJOR_VER $VULN_MINOR_VER`

echo -e "*** NV_CONTAINER_TAG=$NV_CONTAINER_TAG ***"
echo -e "*** NV_BUILD_BRANCH=$NV_BUILD_BRANCH ***"
echo -e "*** JENKINS_JOB_NAME=$JENKINS_JOB_NAME ***"
echo -e "*** JENKINS_BUILD_TAG=$JENKINS_BUILD_TAG ***"
echo -e "*** JENKINS_BUILD_NUMBER=$JENKINS_BUILD_NUMBER ***"
echo -e "*** VULN_VER=$VULN_VER ***"

DOCKER_REPO=10.1.127.3:5000
DOCKER_REPO_REL=10.1.127.12:5000
SAVE_CWD=`pwd`

echo -e "\n*** clean up build containers ***\n"
docker stop build
docker rm build

mkdir -p $JENKINS_BUILD_TAG || { echo "Failed make build dir"; exit 1; }
cd ./$JENKINS_BUILD_TAG || { echo "Failed cd into"; exit 1; }

echo -e "\n*** git clone scanner and sigstore-interface ***\n"
sudo rm -rf scanner
sudo rm -rf sigstore-interface
git clone --depth 1 --branch $NV_BUILD_BRANCH git@github.com:neuvector/scanner.git || { echo "Failed git clone scanner"; exit 1; }
git clone --depth 1 --branch $NV_BUILD_BRANCH git@github.com:neuvector/sigstore-interface.git || { echo "Failed git clone sigstore-interface"; exit 1; }

echo -e "\n*** git clone dbgen ***\n"
git clone --depth 1 git@github.com:neuvector/vul-dbgen.git

echo -e "\n*** copy cvesource ***\n"
cd ./vul-dbgen
sudo rm -f vul-source
git clone --depth 1 git@github.com:neuvector/vul-source.git || { echo "Failed git clone the source"; exit 1; }
cd ../

# Create database
echo -e "\n*** make database ***\n"
cd ./vul-dbgen || { echo "Failed cd into dbgen"; exit 1; }
VULN_VER=$VULN_VER make db || { echo "Failed make db"; exit 1; }
mkdir -p ../scanner/data
cp cvedb.regular ../scanner/data/
cp cvedb.compact ../scanner/data/
cd ../

# Create binary and database

echo -e "\n*** build sigstore-interface binary ***\n"
cd ./sigstore-interface

GITREV=`git rev-parse --short HEAD`
echo -e "*** GITREV=$GITREV ***\n"

echo -e "\n*** make binary ***\n"
make binary || { echo "Failed make binary"; exit 1; }

cd ..

echo -e "\n*** build scanner binary ***\n"
cd ./scanner || { echo "Failed cd into scanner"; exit 1; }

git checkout $NV_BUILD_BRANCH || { echo "Failed checkout $NV_BUILD_BRANCH"; exit 1; }

GITREV=`git rev-parse --short HEAD`
echo -e "*** GITREV=$GITREV ***\n"

echo -e "\n*** make binary ***\n"
make binary || { echo "Failed make binary"; exit 1; }

echo -e "\n*** clean up <none> containers ***\n"
docker images -q --filter "dangling=true" | xargs docker rmi

echo -e "\n*** clean up scanner containers ***\n"
docker rmi -f $(docker images | grep "neuvector/scanner" | awk '{print $3}')

cd .. || { echo "Failed cd into the parent"; exit 1; }

# Make image

echo -e "\n*** write version label ***\n"
cd ./scanner/build
sed -i -e 's/git.xxxx/'"$GITREV"'/g' ./Dockerfile.scanner
sed -i -e 's/vuln.xxxx/'"$VULN_VER"'/g' ./Dockerfile.scanner
cd ../../

echo -e "\n*** copy Makefile ***\n"
cp scanner/Makefile Makefile || { echo "Failed to copy Makefile"; exit 1; }
cp scanner/build/dockerignore .dockerignore

echo -e "\n*** build scanner container ***\n"
make scanner_image || { echo "Failed to make scanner image"; exit 1; }

echo -e "\n*** publish scanner images ***\n"
docker tag neuvector/scanner $DOCKER_REPO/neuvector/scanner:$NV_TAG_AS || { echo "Failed to docker tag scanner as $NV_TAG_AS"; exit 1; }
docker push $DOCKER_REPO/neuvector/scanner:$NV_TAG_AS || { echo "Failed to docker push scanner as $NV_TAG_AS"; exit 1; }
if [ "$NV_REL_AS" == "latest" ]; then
    docker tag neuvector/scanner $DOCKER_REPO/neuvector/scanner:$NV_CONTAINER_TAG || { echo "Failed to docker tag scanner"; exit 1; }
    docker push $DOCKER_REPO/neuvector/scanner:$NV_CONTAINER_TAG || { echo "Failed to docker push scanner"; exit 1; }

    docker tag neuvector/scanner $DOCKER_REPO/neuvector/scanner:latest || { echo "Failed to docker tag scanner as latest"; exit 1; }
    docker push $DOCKER_REPO/neuvector/scanner:latest || { echo "Failed to docker push scanner"; exit 1; }
fi

cd $SAVE_CWD

echo -e "\n*** GITREV=$GITREV ***"
echo -e "*** scanner image: neuvector/scanner:$NV_CONTAINER_TAG***"
echo -e "*** vuln. database: $VULN_VER***"

echo -e "\n******************* Scanner $NV_BUILD_BRANCH Build Succeed *******************\n"

exit 0
