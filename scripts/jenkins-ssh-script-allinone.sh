############################### jenkins ssh command ################################
#
# echo -e "\n*** clone release ***\n"
# rm -rf release
# git clone git@github.com:neuvector/release.git || { echo "Failed to clone release"; exit 1; }
#
# release/scripts/jenkins-ssh-script-allinone.sh default master $JOB_NAME $BUILD_TAG $BUILD_NUMBER "$ParentFleetBuildTag" "$ParentManagerBuildTag"
#
# exit 0
#
set -x

echo -e "\n******************* Allinone Build Start *******************\n"

NV_BUILD_TARGET=$1
NV_BUILD_BRANCH=$2
JENKINS_JOB_NAME=$3
JENKINS_BUILD_TAG=$4
JENKINS_BUILD_NUMBER=$5
ParentFleetBuildTag=$6
ParentManagerBuildTag=$7
GITHUB_REPO=$8

FLEET_PROJECT="nv-build-fleet"
TO_BUILD_DAOCLOUD=false
NV_CONTAINER_TAG_SUFFIX=""
case "$NV_BUILD_TARGET" in
	default)
		MANAGER_PROJECT="nv-build-manager"
		;;
	daocloud)
		TO_BUILD_DAOCLOUD=true
		MANAGER_PROJECT="nv-build-manager-daocloud"
		NV_CONTAINER_TAG_SUFFIX=".daocloud"
		;;
	sonatype)
		MANAGER_PROJECT="nv-build-manager-sonatype"
		NV_CONTAINER_TAG_SUFFIX=".sonatype"
		;;
	*)
		echo "Failed to parse image target: $NV_BUILD_TARGET"
		exit 1;
esac

TO_TAG_LATEST=false
if [[ "$NV_BUILD_TARGET" == "default" ]] && [[ "$NV_BUILD_BRANCH" == "main" ]]; then
	TO_TAG_LATEST=true
fi

NV_CONTAINER_TAG=$JENKINS_BUILD_TAG
FLEET_PROJECT="jenkins-"$FLEET_PROJECT
MANAGER_PROJECT="jenkins-"$MANAGER_PROJECT

echo -e "*** NV_BUILD_TARGET=$NV_BUILD_TARGET ***"
echo -e "*** NV_BUILD_BRANCH=$NV_BUILD_BRANCH ***"
echo -e "*** NV_CONTAINER_TAG=$NV_CONTAINER_TAG$NV_CONTAINER_TAG_SUFFIX ***"
echo -e "*** JENKINS_JOB_NAME=$JENKINS_JOB_NAME ***"
echo -e "*** JENKINS_BUILD_TAG=$JENKINS_BUILD_TAG ***"
echo -e "*** JENKINS_BUILD_NUMBER=$JENKINS_BUILD_NUMBER ***"

DOCKER_REPO="10.1.127.3:5000"
DOCKER_REPO_REL="10.1.127.12:5000"

mkdir -p $JENKINS_BUILD_TAG || { echo "Failed mkdir $JENKINS_BUILD_TAG"; exit 1; }
cd ./$JENKINS_BUILD_TAG || { echo "Failed cd into"; exit 1; }

# Locate fleet's latest build
# echo -e "\n*** locating fleet's latest build ***\n"
# if [ -z "$ParentFleetBuildTag" ]; then
#    ParentFleetBuildTag=$(echo $FLEET_PROJECT"-"`ls ../* 2>&1 | grep -Eo $FLEET_PROJECT"-[0-9]+" | awk -F"-" '{print f$NF}' | awk '{if ($1 > max) max=$1}END{print max}'`)
# fi

# echo -e "\n*** pull binary from \$ParentFleetBuildTag=$ParentFleetBuildTag ***\n"
# docker import ../$ParentFleetBuildTag/controller.tar.gz neuvector/controller:$NV_CONTAINER_TAG
# docker import ../$ParentFleetBuildTag/enforcer.tar.gz neuvector/enforcer:$NV_CONTAINER_TAG

# echo -e "\n*** locating manager's latest build ***\n"
# if [ -z "$ParentManagerBuildTag" ]; then
#     ParentManagerBuildTag=$(echo $MANAGER_PROJECT"-"`ls ../* 2>&1 | grep -Eo $MANAGER_PROJECT"-[0-9]+" | awk -F"-" '{print f$NF}' | awk '{if ($1 > max) max=$1}END{print max}'`)
# fi
# echo -e "\n*** pull binary from \$ParentManagerBuildTag=$ParentManagerBuildTag ***\n"
# docker import ../$ParentManagerBuildTag/manager.tar.gz neuvector/manager:$JENKINS_BUILD_TAG

echo -e "\n*** git clone allinone ***\n"
sudo -S rm -rf allinone
git clone --depth 1 --branch $NV_BUILD_BRANCH https://github.com/neuvector/allinone || { echo "Failed git clone"; exit 1; }

cd ./allinone || { echo "Failed cd into"; exit 1; }

echo -e "\n*** clean up allinone container ***\n"
docker rmi -f $(docker images | grep "neuvector/allinone" | awk '{print $3}')

GITREV=`git rev-parse --short HEAD`
echo -e "*** GITREV=$GITREV ***\n"

# Use docker legacy builder to workaround TLS verification issue for internal registry
docker build -f package/Dockerfile \
	--build-arg NV_VERSION=latest --build-arg SRCREPO=$DOCKER_REPO/neuvector \
	--build-arg VERSION=$GITREV -t "neuvector/allinone:$NV_CONTAINER_TAG" --pull .

echo -e "\n*** publish allinone container ***\n"
docker tag neuvector/allinone:$NV_CONTAINER_TAG $DOCKER_REPO/neuvector/allinone:$NV_CONTAINER_TAG$NV_CONTAINER_TAG_SUFFIX || { echo "Failed to docker tag allinone"; exit 1; }
docker push $DOCKER_REPO/neuvector/allinone:$NV_CONTAINER_TAG$NV_CONTAINER_TAG_SUFFIX || { echo "Failed to docker push allinone"; exit 1; }
if [ "$TO_TAG_LATEST" = true ]; then
    docker tag neuvector/allinone:$NV_CONTAINER_TAG $DOCKER_REPO/neuvector/allinone:latest || { echo "Failed to docker tag allinone as latest"; exit 1; }
    docker push $DOCKER_REPO/neuvector/allinone:latest || { echo "Failed to docker push allinone latest"; exit 1; }
fi

echo -e "\n*** ParentFleetBuildTag: $ParentFleetBuildTag ***"
echo -e "*** ParentManagerBuildTag: $ParentManagerBuildTag ***"
echo -e "*** allinone image: neuvector/allinone:$NV_CONTAINER_TAG$NV_CONTAINER_TAG_SUFFIX ***"

echo -e "\n******************* Allinone Build Succeed *******************\n"

exit 0
