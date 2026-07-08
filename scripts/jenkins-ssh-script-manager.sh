############################### jenkins ssh command ################################
#
# echo -e "\n*** clone release ***\n"
# rm -rf release
# git clone git@github.com:neuvector/release.git || { echo "Failed to clone release"; exit 1; }
#
# echo -e "\n*** clean up jenkins-$JOB_NAME* ***\n"
# sudo -S rm -rf jenkins-$JOB_NAME*
#
# BRANCH_NAME=${GIT_BRANCH#*/}
#
# release/scripts/jenkins-ssh-script-manager.sh default $BRANCH_NAME $JOB_NAME $BUILD_TAG $BUILD_NUMBER
#
# exit 0
#
set -x
echo -e "\n******************* Manager Build Start *******************\n"

NV_BUILD_TARGET=$1
NV_BUILD_BRANCH=$2
JENKINS_JOB_NAME=$3
JENKINS_BUILD_TAG=$4
JENKINS_BUILD_NUMBER=$5
GITHUB_REPO=$6

TO_BUILD_DAOCLOUD=false
TO_BUILD_SONATYPE=false
NV_CONTAINER_TAG_SUFFIX=""
case "$NV_BUILD_TARGET" in
	default)
		;;
	daocloud)
		TO_BUILD_DAOCLOUD=true
		NV_CONTAINER_TAG_SUFFIX=".daocloud"
		;;
	sonatype)
		TO_BUILD_SONATYPE=true
		NV_CONTAINER_TAG_SUFFIX=".sonatype"
		;;
	*)
		echo "Failed to parse image target: $NV_BUILD_TARGET"
		exit 1;
esac

# Tag starts with 'v', branch does not
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

echo -e "\n*** git clone manager ***\n"
sudo -S rm -rf manager
git clone --depth 1 --branch $NV_BUILD_BRANCH https://github.com/neuvector/manager manager || { echo "Failed git clone manager"; exit 1; }

cd ./manager || { echo "Failed cd into"; exit 1; }

GITREV=`git rev-parse --short HEAD`
echo -e "\n*** GITREV=$GITREV ***\n"

if [ "$TO_BUILD_DAOCLOUD" = true ]; then
    echo -e "\n*** prepare daocloud logo files ***\n"

    cp -f ./admin/webapp/root/app/views/partials/dss-eula.html ./admin/webapp/root/app/views/partials/eulaContent.html || { echo "Failed ovwrite eulaContent.html"; exit 1; }
    cp -f ./admin/webapp/root/app/views/partials/dss-footer.html ./admin/webapp/root/app/views/partials/footer.html || { echo "Failed ovwrite footer.html"; exit 1; }
    cp -f ./admin/webapp/root/app/views/partials/dss-sidebar.html ./admin/webapp/root/app/views/partials/sidebar.html || { echo "Failed ovwrite footer.html"; exit 1; }
    cp -f ./admin/webapp/root/app/img/daoCloud_logo/*.png ./admin/webapp/root/app/img/ || { echo "Failed overwrite png files"; exit 1; }
	cp -f ./admin/webapp/root/app/img/daoCloud_logo/preloader.empty.png ./admin/webapp/root/app/img/preloader/ || { echo "Failed overwrite preloader files"; exit 1; }
    cp -f ./admin/webapp/root/app/img/daoCloud_logo/preloader.full.png ./admin/webapp/root/app/img/preloader/ || { echo "Failed overwrite preloader files"; exit 1; }
    cp -f ./admin/webapp/root/master/templates/index-dss.html ./admin/webapp/root/master/templates/index.html || { echo "Failed ovwrite index.html"; exit 1; }
	rm -rf ./admin/webapp/root/master/i18n/zh_cn/zh_cn_neuvector.json || { echo "Failed remove zh_cn_neuvector.json"; exit 1; }
	cp -f ./admin/webapp/root/master/i18n_partner/zh_cn_DSS.json ./admin/webapp/root/master/i18n/zh_cn/zh_cn_DSS.json || { echo "Failed copy zh_cn_DSS.json"; exit 1; }
	rm -rf ./admin/webapp/root/master/i18n/en/en_neuvector.json || { echo "Failed remove en_neuvector.json"; exit 1; }
	cp -f ./admin/webapp/root/master/i18n_partner/en_DSS.json ./admin/webapp/root/master/i18n/en/en_DSS.json || { echo "Failed copy en_DSS.json"; exit 1; }

    sed -i -e "s/'en'/'zh_cn'/g" ./admin/webapp/root/master/js/modules/translate/translate.config.js
    sed -i -e 's/NeuVector Security Console/'"DaoCloud 云原生安全平台"'/g' ./admin/webapp/root/master/js/modules/settings/settings.run.js
    sed -i -e 's/NeuVector/'"DaoCloud"'/g' ./admin/webapp/root/master/js/modules/settings/settings.run.js
elif [ "$TO_BUILD_SONATYPE" = true ]; then
    echo -e "\n*** prepare Sonatype logo files ***\n"

    cp -f ../../release/sonatype/sonatype-footer.html ./admin/webapp/websrc/app/frame/footer/footer.component.html || { echo "Failed ovwrite footer.html"; exit 1; }
    cp -f ../../release/sonatype/*.png ./admin/webapp/websrc/assets/img || { echo "Failed overwrite png files"; exit 1; }
    cp -f ../../release/sonatype/preloader.full.png ./admin/webapp/websrc/assets/img/systemPrepare/systemPrepare.full.png || { echo "Failed overwrite png files"; exit 1; }
    cp -f ../../release/sonatype/index-sonatype.html ./admin/webapp/websrc/index.html || { echo "Failed ovwrite index.html"; exit 1; }
    cp -f ../../release/sonatype/en_sonatype.json ./admin/webapp/websrc/assets/i18n/en-partner.json || { echo "Failed copy en_sonatype.json"; exit 1; }

	sed -i -e 's/NeuVector Security Console/'"Nexus Container Security Console"'/g' ./admin/webapp/root/app_src/js/infra/settings/settings.run.js
    sed -i -e 's/NeuVector/'"Sonatype"'/g' ./admin/webapp/root/app_src/js/infra/settings/settings.run.js
fi

echo -e "\n*** clean up <none> images ***\n"
docker images -q --filter "dangling=true" | xargs docker rmi

echo -e "\n*** clean up manager images ***\n"
docker rmi -f $(docker images | grep "neuvector/manager" | awk '{print $3}')

# Make image

echo -e "\n*** build manager container ***\n"
TARGET_PLATFORMS=linux/amd64 TAG=$NV_CONTAINER_TAG VERSION=vinterim.$JENKINS_BUILD_NUMBER make build-image

echo -e "\n*** publish manager container ***\n"
if [ -z "$GITHUB_REPO" ]; then
    docker tag neuvector/manager:$NV_CONTAINER_TAG $DOCKER_REPO/neuvector/manager:$NV_CONTAINER_TAG$NV_CONTAINER_TAG_SUFFIX || { echo "Failed to docker tag manager"; exit 1; }
    docker push $DOCKER_REPO/neuvector/manager:$NV_CONTAINER_TAG$NV_CONTAINER_TAG_SUFFIX || { echo "Failed to docker push manager"; exit 1; }
    if [ "$TO_TAG_LATEST" = true ]; then
        docker tag neuvector/manager:$NV_CONTAINER_TAG $DOCKER_REPO/neuvector/manager:latest || { echo "Failed to docker tag manager as latest"; exit 1; }
        docker push $DOCKER_REPO/neuvector/manager:latest || { echo "Failed to docker push manager"; exit 1; }
    fi
fi

cd $SAVE_CWD

echo -e "\n*** GITREV: $GITREV ***"
echo -e "*** manager image: neuvector/manager:$NV_CONTAINER_TAG$NV_CONTAINER_TAG_SUFFIX ***"

echo -e "\n******************* Manager Build Succeed *******************\n"

exit 0
