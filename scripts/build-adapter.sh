# This script is to build adapter with github action
#
echo -e "\n******************* Scanner $NV_BUILD_BRANCH Build Start *******************\n"

NV_BUILD_BRANCH=$1

# Tag starts with 'v', branch does not
TO_BUILD_BRANCH=true
if [[ "$NV_BUILD_BRANCH" == v* ]]; then
	TO_BUILD_BRANCH=false
fi
TO_TAG_LATEST=true

if [ "$TO_BUILD_BRANCH" = true ]; then
	NV_CONTAINER_TAG=$JENKINS_BUILD_TAG
else
	# Remove first 'v'
	NV_CONTAINER_TAG=${NV_BUILD_BRANCH#v}
fi

echo -e "*** NV_BUILD_BRANCH=$NV_BUILD_BRANCH ***"
echo -e "*** NV_CONTAINER_TAG=$NV_CONTAINER_TAG ***"

SAVE_CWD=`pwd`

mkdir -p stage || { echo "Failed make build dir"; exit 1; }

echo -e "\n*** git clone adapter ***\n"
rm -rf registry-adapter
git clone --depth 1 https://github.com/neuvector/registry-adapter

echo -e "\n*** build registry-adapter binary ***\n"
cd ./registry-adapter

GITREV=`git rev-parse --short HEAD`
echo -e "*** GITREV=$GITREV ***\n"

echo -e "\n*** write version files ***\n"
if [ "$TO_BUILD_BRANCH" = true ]; then
    sed -i -e 's/xxxx/'"$JENKINS_BUILD_NUMBER"'/g' ./version.go
else
    sed -i -e 's/interim.*xxxx/'"$NV_BUILD_BRANCH"'/g' ./version.go
fi

echo -e "\n*** make binary ***\n"
make binary || { echo "Failed make binary"; exit 1; }

cd ..

# Make image

echo -e "\n*** write version label ***\n"
cd ./registry-adapter/build
sed -i -e 's/git.xxxx/'"$GITREV"'/g' ./Dockerfile
cd ../../

echo -e "\n*** copy Makefile ***\n"

cp registry-adapter/Makefile . || { echo "Failed to copy Makefile"; exit 1; }
cp registry-adapter/build/dockerignore .dockerignore

echo -e "\n*** build adapter container ***\n"
make adapter_image NV_TAG=$NV_CONTAINER_TAG || { echo "Failed to make adapter image"; exit 1; }

cd $SAVE_CWD

echo -e "\n*** GITREV=$GITREV ***"
echo -e "*** registry-adapter image: neuvector/registry-adapter:$NV_CONTAINER_TAG ***"

echo -e "\n******************* Adapter Build Succeed *******************\n"

exit 0
