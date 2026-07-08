############################### jenkins ssh command ################################
#
# echo -e "\n*** clone release ***\n"
# rm -rf release
# git clone git@github.com:neuvector/release.git || { echo "Failed to clone release"; exit 1; }
#
# sudo -S rm -rf jenkins-$JOB_NAME*
#
# release/scripts/jenkins-ssh-script-release.sh default $NV_RELEASE_TAG $JOB_NAME $BUILD_TAG $BUILD_NUMBER
#
# exit 0
#

echo -e "\n******************* Release Build Start *******************\n"

NV_BUILD_TARGET=$1
NV_BUILD_BRANCH=$2
JENKINS_JOB_NAME=$3
JENKINS_BUILD_TAG=$4
JENKINS_BUILD_NUMBER=$5
GITHUB_REPO=$6

echo -e "*** NV_BUILD_TARGET=$NV_BUILD_TARGET ***"
echo -e "*** NV_BUILD_BRANCH=$NV_BUILD_BRANCH ***"
echo -e "*** JENKINS_JOB_NAME=$JENKINS_JOB_NAME ***"
echo -e "*** JENKINS_BUILD_TAG=$JENKINS_BUILD_TAG ***"
echo -e "*** JENKINS_BUILD_NUMBER=$JENKINS_BUILD_NUMBER ***"

release/scripts/jenkins-ssh-script-fleet.sh $NV_BUILD_TARGET $NV_BUILD_BRANCH $JENKINS_JOB_NAME $JENKINS_BUILD_TAG $JENKINS_BUILD_NUMBER $GITHUB_REPO || { echo "Failed to build fleet"; exit 1; }
release/scripts/jenkins-ssh-script-manager.sh $NV_BUILD_TARGET $NV_BUILD_BRANCH $JENKINS_JOB_NAME $JENKINS_BUILD_TAG $JENKINS_BUILD_NUMBER $GITHUB_REPO || { echo "Failed to build manager"; exit 1; }
release/scripts/jenkins-ssh-script-allinone.sh $NV_BUILD_TARGET $NV_BUILD_BRANCH $JENKINS_JOB_NAME $JENKINS_BUILD_TAG $JENKINS_BUILD_NUMBER $GITHUB_REPO || { echo "Failed to build allinone"; exit 1; }

echo -e "\n*** release target: $NV_BUILD_TARGET ***"
echo -e "\n*** release version: $NV_BUILD_BRANCH ***"

echo -e "\n******************* Release Build Succeed *******************\n"

exit 0

