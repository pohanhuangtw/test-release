############################### jenkins ssh command ################################
#
# echo -e "\n*** clone build ***\n"
# rm -rf release
# git clone git@github.com:neuvector/release.git || { echo "Failed to clone release repo"; exit 1; }
#
# echo -e "\n*** clean up jenkins-$JOB_NAME* ***\n"
# sudo -S rm -rf jenkins-$JOB_NAME*
#
# BRANCH_NAME=${GIT_BRANCH#*/}
#
# release/scripts/jenkins-ssh-script-fleet.sh default $BRANCH_NAME $JOB_NAME $BUILD_TAG $BUILD_NUMBER
#
# exit 0
#
set -x
echo -e "\n******************* Fleet Build Start *******************\n"

NV_BUILD_TARGET=$1
NV_BUILD_BRANCH=$2
JENKINS_JOB_NAME=$3
JENKINS_BUILD_TAG=$4
JENKINS_BUILD_NUMBER=$5
GITHUB_REPO=$6

NV_CONTAINER_TAG_SUFFIX=""
case "$NV_BUILD_TARGET" in
	default)
		;;
	daocloud)
		NV_CONTAINER_TAG_SUFFIX=".daocloud"
		;;
	sonatype)
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

echo -e "*** NV_BUILD_TARGET=$NV_BUILD_TARGET ***"
echo -e "*** NV_BUILD_BRANCH=$NV_BUILD_BRANCH ***"
echo -e "*** NV_CONTAINER_TAG=$NV_CONTAINER_TAG$NV_CONTAINER_TAG_SUFFIX ***"
echo -e "*** JENKINS_JOB_NAME=$JENKINS_JOB_NAME ***"
echo -e "*** JENKINS_BUILD_TAG=$JENKINS_BUILD_TAG ***"
echo -e "*** JENKINS_BUILD_NUMBER=$JENKINS_BUILD_NUMBER ***"

DOCKER_REPO=10.1.127.3:5000
DOCKER_REPO_REL=10.1.127.12:5000
SAVE_CWD=`pwd`

echo -e "\n*** clean up build containers ***\n"
docker stop build
docker rm build

mkdir -p $JENKINS_BUILD_TAG || { echo "Failed make build dir"; exit 1; }
cd ./$JENKINS_BUILD_TAG|| { echo "Failed cd into"; exit 1; }

echo -e "\n*** git clone neuvector ***\n"
sudo -S rm -rf neuvector
git clone --depth 1 --branch $NV_BUILD_BRANCH https://github.com/neuvector/neuvector || { echo "Failed git clone"; exit 1; }

cd ./neuvector || { echo "Failed cd into"; exit 1; }

GITREV=`git rev-parse --short HEAD`
echo -e "*** GITREV=$GITREV ***\n"

echo -e "\n*** copy keys.go ***\n"
cp ../../release/keys.go ./share/utils/ || { echo "Failed to copy keys.go"; exit 1; }

echo -e "\n*** clean up <none> images ***\n"
docker images -q --filter "dangling=true" | xargs docker rmi

echo -e "\n*** clean up fleet images ***\n"
docker rmi -f $(docker images | grep "neuvector/controller" | awk '{print $3}')
docker rmi -f $(docker images | grep "neuvector/enforcer" | awk '{print $3}')

echo -e "\n*** build controller container ***\n"
TARGET_PLATFORMS=linux/amd64 TAG=$NV_CONTAINER_TAG VERSION=vinterim.$JENKINS_BUILD_NUMBER make build-controller-image

echo -e "\n*** build enforcer container ***\n"
TARGET_PLATFORMS=linux/amd64 TAG=$NV_CONTAINER_TAG VERSION=vinterim.$JENKINS_BUILD_NUMBER make build-enforcer-image

# echo -e "\n*** build fetcher container ***\n"
# make fetcher_image || { echo "Failed to make fetcher image"; exit 1; }

echo -e "\n*** publish images ***\n"
if [ -z "$GITHUB_REPO" ]; then
    docker tag neuvector/controller:$NV_CONTAINER_TAG $DOCKER_REPO/neuvector/controller:$NV_CONTAINER_TAG$NV_CONTAINER_TAG_SUFFIX || { echo "Failed to docker tag controller"; exit 1; }
    docker tag neuvector/enforcer:$NV_CONTAINER_TAG $DOCKER_REPO/neuvector/enforcer:$NV_CONTAINER_TAG$NV_CONTAINER_TAG_SUFFIX || { echo "Failed to docker tag enforcer"; exit 1; }
    docker push $DOCKER_REPO/neuvector/controller:$NV_CONTAINER_TAG$NV_CONTAINER_TAG_SUFFIX || { echo "Failed to docker push controller"; exit 1; }
    docker push $DOCKER_REPO/neuvector/enforcer:$NV_CONTAINER_TAG$NV_CONTAINER_TAG_SUFFIX || { echo "Failed to docker push enforcer"; exit 1; }
    if [ "$TO_TAG_LATEST" = true ]; then
        docker tag neuvector/controller:$NV_CONTAINER_TAG $DOCKER_REPO/neuvector/controller:latest || { echo "Failed to docker tag controller as latest"; exit 1; }
        docker tag neuvector/enforcer:$NV_CONTAINER_TAG $DOCKER_REPO/neuvector/enforcer:latest || { echo "Failed to docker tag enforcer as latest"; exit 1; }
        docker push $DOCKER_REPO/neuvector/controller:latest || { echo "Failed to docker push controller"; exit 1; }
        docker push $DOCKER_REPO/neuvector/enforcer:latest || { echo "Failed to docker push enforcer"; exit 1; }
    fi
fi

cd $SAVE_CWD

echo -e "\n*** GITREV=$GITREV ***"
echo -e "*** controller image: neuvector/controller:$NV_CONTAINER_TAG$NV_CONTAINER_TAG_SUFFIX ***"
echo -e "*** enforcer image: neuvector/enforcer:$NV_CONTAINER_TAG$NV_CONTAINER_TAG_SUFFIX ***"

echo -e "\n******************* Fleet Build Succeed *******************\n"

exit 0
