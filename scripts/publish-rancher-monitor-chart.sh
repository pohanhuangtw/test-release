#!/bin/bash
##################### Update upstream NeuVector helm as per rancher chart requirement ##########
# get current version
# curl -k -L  https://raw.githubusercontent.com/rancher/charts/refs/heads/release-v2.10/index.yaml |yq .entries.neuvector-monitor[].version |head -n1
# curl -k -L  https://raw.githubusercontent.com/rancher/charts/refs/heads/release-v2.9/index.yaml |yq .entries.neuvector-monitor[].version |head -n1
# curl -k -L  https://raw.githubusercontent.com/rancher/charts/refs/heads/release-v2.8/index.yaml |yq .entries.neuvector-monitor[].version |head -n1
#
#
# version do not have v prefix


if [ $# = 0 ];then
  echo "$0 <chart version>"
  exit
fi

_CHART_VER_=$1

_RANCHER_REPO_=https://github.com/rancher/charts.git
_FORK_REPO_=https://github.com/neuvector/rancher-charts.git
_HELM_REPO_=https://neuvector.github.io/neuvector-helm
_QLOC_=https://raw.githubusercontent.com/neuvector/misc/rancher/main/questions-monitor.yaml
_APPLOC_=https://raw.githubusercontent.com/neuvector/misc/rancher/main/app-readme-monitor.md

_FIRST_DIGIT_=`echo $_CHART_VER_ | awk -F. '{print $1}'`

if [ $_FIRST_DIGIT_ = "103" ];then
  _RANCHER_VERSION_=2.8.0-0
  _RANCHER_VERSION1_=2.9.0-0
  _NVBRANCH_=nv-monitor-dev-v2.8
  _RBRANCH_=dev-v2.8
elif [ $_FIRST_DIGIT_ = "104" ];then
  _RANCHER_VERSION_=2.9.0-0
  _RANCHER_VERSION1_=2.10.0-0
  _NVBRANCH_=nv-monitor-dev-v2.9
  _RBRANCH_=dev-v2.9
elif [ $_FIRST_DIGIT_ = "105" ];then
  _RANCHER_VERSION_=2.10.0-0
  _RANCHER_VERSION1_=2.11.0-0
  _NVBRANCH_=nv-monitor-dev-v2.10
  _RBRANCH_=dev-v2.10
fi


#### fetch and merge rancher branch
git remote add upstream $_RANCHER_REPO_
git checkout $_RBRANCH_
git fetch upstream $_RBRANCH_
git merge upstream/$_RBRANCH_
git push --set-upstream origin $_RBRANCH_

#### delete and create again neuvector branch

git branch -B $_NVBRANCH_
git reset $_RBRANCH_ --hard


_WORKING_DIR_=/tmp/rancher/helm-monitor

if [ ! -d $_WORKING_DIR_ ]; then
  echo " Creating directory"
  mkdir -p $_WORKING_DIR_
else
  echo "Clean directory"
  rm -rf $_WORKING_DIR_/*
fi

cd $_WORKING_DIR_

helm repo add neuvector $_HELM_REPO_
helm repo update
helm fetch neuvector/monitor --devel
_MONITOR_VER_=`helm search repo --devel| grep neuvector/monitor | awk '{print $2}'`


tar zxf monitor-${_MONITOR_VER_}.tgz

cd $_WORKING_DIR_/monitor
#Updating Chart.yaml
echo "Monitor Updating Chart"
cat > .Chart.yaml << EOF
annotations:
  catalog.cattle.io/certified: rancher
  catalog.cattle.io/display-name: 'NeuVector Monitor'
  catalog.cattle.io/kube-version: '>=1.18.0-0 < 1.32.0-0'
  catalog.cattle.io/namespace: cattle-neuvector-system
  catalog.cattle.io/os: linux
  catalog.cattle.io/permits-os: linux
  catalog.cattle.io/rancher-version: '>= start < end'
  catalog.cattle.io/provides-gvr: neuvector.com/v1
  catalog.cattle.io/release-name: neuvector-monitor
  catalog.cattle.io/type: cluster-tool
  catalog.cattle.io/upstream-version: _VER_
keywords:
- security
EOF

### Update supported rancher version as per chart version

if [ $_FIRST_DIGIT_ = "103" ];then
  _RANCHER_VERSION_=2.8.0-0
  _RANCHER_VERSION1_=2.9.0-0
  sed -i "s/start/$_RANCHER_VERSION_/" .Chart.yaml
  sed -i "s/end/$_RANCHER_VERSION1_/" .Chart.yaml
elif [ $_FIRST_DIGIT_ = "104" ];then
  _RANCHER_VERSION_=2.9.0-0
  _RANCHER_VERSION1_=2.10.0-0
  sed -i "s/start/$_RANCHER_VERSION_/" .Chart.yaml
  sed -i "s/end/$_RANCHER_VERSION1_/" .Chart.yaml
elif [ $_FIRST_DIGIT_ = "105" ];then
  _RANCHER_VERSION_=2.10.0-0
  _RANCHER_VERSION1_=2.11.0-0
  sed -i "s/start/$_RANCHER_VERSION_/" .Chart.yaml
  sed -i "s/end/$_RANCHER_VERSION1_/" .Chart.yaml
fi


cat Chart.yaml >> .Chart.yaml
sed -i 's/name: monitor/name: neuvector-monitor/' .Chart.yaml
sed -i  /engine/d .Chart.yaml
sed -i "/version: $_MONITOR_VER_/i sources:\n- https://github.com/neuvector/neuvector"  .Chart.yaml
sed -i "s/_VER_/$_MONITOR_VER_/" .Chart.yaml
sed -i 's|description: Helm chart for NeuVector monitor services|description: Helm feature chart (optional) add-on to NeuVector for monitoring with Prometheus/Grafana.|' .Chart.yaml
mv .Chart.yaml Chart.yaml
wget $_QLOC_ 
wget $_APPLOC_
mv app-readme-monitor.md app-readme.md
mv questions-monitor.yaml questions.yaml
VALUE_LINK="https://github.com/neuvector/neuvector-helm/blob/master/charts/monitor/values.yaml"
#sed -i 's|(values.yaml)|(https://github.com/neuvector/neuvector-helm/tree/2.2.2/charts/core/values.yaml)|' README.md
sed -i "s|(values.yaml)|($VALUE_LINK)|" README.md
sed -i /Contact/d README.md

_TAG_=`grep "^    tag:" values.yaml | awk '{print $2}'`
_APP_VER_=`grep appVersion: Chart.yaml|awk '{print $2}'`
_TAG1_='5.3.0'
cp values.yaml .values.yaml


echo "Monitor Updating images in values"
sed -i 's|repository: neuvector/prometheus-exporter|repository: rancher/neuvector-prometheus-exporter|' .values.yaml
#sed -i "s|tag: $_TAG_|tag: $_TAG1_|" .values.yaml
sed -i "s|tag: $_TAG_|tag: $_APP_VER_|" .values.yaml
sed -i "/# Declare/a \ \ \ \ systemDefaultRegistry: \"\"" .values.yaml
sed -i "/# Declare/a \ \ cattle:" .values.yaml
sed -i "/# Declare/a global:" .values.yaml
sed -E -i 's/(# Declare.*)/\1\n/' .values.yaml
mv .values.yaml values.yaml


#Updating templates
echo "Core Updating Template"

cd $_WORKING_DIR_/monitor/templates

sed -i 's|image: "{{ .Values.registry }}/{{ .Values.exporter.image.repository }}:{{ .Values.exporter.image.tag }}"|image: {{ template "system_default_registry" . }}{{ .Values.exporter.image.repository }}:{{ .Values.exporter.image.tag }}|' exporter-deployment.yaml



cat > .helper << EOF

{{- define "system_default_registry" -}}
{{- if .Values.global.cattle.systemDefaultRegistry -}}
{{- printf "%s/" .Values.global.cattle.systemDefaultRegistry -}}
{{- else -}}
{{- "" -}}
{{- end -}}
{{- end -}}
EOF

cat .helper >> _helpers.tpl
rm .helper




export PACKAGE=neuvector-monitor
_CHART_DIR_=$CHART_DIR
_NV_PKG_DIR_=$CHART_DIR/packages/neuvector-monitor
_NV_HELM_CHART_DIR_=/tmp/rancher/helm-monitor

# To remove unreleased version chart
function _remove_unreleased  {
      cd $_CHART_DIR_
      make remove CHART=neuvector VERSION=101.0.2+up2.4.0
      git add .
      git commit -m "Remove charts/assets for neuvector 101.0.2+up2.4.0"
      git push --set-upstream origin $_NVBRANCH_
      make remove CHART=neuvector-crd VERSION=101.0.2+up2.4.0
      git add .
      git commit -m "Remove charts/assets for neuvector-crd 101.0.2+up2.4.0"
      git push --set-upstream origin  $_NVBRANCH_
}


_MONITOR_VER_=`helm search repo --devel| grep neuvector/monitor | awk '{print $2}'`

echo "Rancher Chart directory: $_CHART_DIR_"  
echo "NeuvectorPackage directory: $_NV_PKG_DIR_" 
echo "Neuvector Helm Directory: $_NV_HELM_CHART_DIR_" 
echo "Neuvector Helm Monitor Version: $_MONITOR_VER_" 

echo -n "Provide Neuvector Monitor Rancher Chart Version:"
_CHART_VER_=$1
echo "Neuvector Monitor Rancher Chart Version: $_CHART_VER_"

#Create dir 
if [ ! -d $_NV_PKG_DIR_ ]; then
  echo "Creating directory"
  mkdir $_NV_PKG_DIR_
fi

cd $_NV_PKG_DIR_
git checkout $_NVBRANCH_
#cp $_NV_HELM_CHART_DIR_/neuvector/package-no-addchart.yaml $_NV_PKG_DIR_/package.yaml

cat > $_NV_PKG_DIR_/package.yaml << EOF
url: https://neuvector.github.io/neuvector-helm/monitor-VER.tgz
version: _CHART_VER_
EOF

sed -i "1s/VER/$_MONITOR_VER_/" $_NV_PKG_DIR_/package.yaml 
sed -i "s/_CHART_VER_/${_CHART_VER_}/" $_NV_PKG_DIR_/package.yaml 

### Change to main chart

cd $_CHART_DIR_
rm -rf $_NV_PKG_DIR_/templates/
rm -rf $_NV_PKG_DIR_/generated-changes/


make prepare
#find $_NV_PKG_DIR_

#cp $_NV_HELM_CHART_DIR_/crd/templates/_helpers.tpl $_NV_PKG_DIR_/charts/crds
cp $_NV_HELM_CHART_DIR_/monitor/* $_NV_PKG_DIR_/charts/
cp $_NV_HELM_CHART_DIR_/monitor/templates/* $_NV_PKG_DIR_/charts/templates/
make patch


function replace_version {

nv_line=`grep neuvector: release.yaml -n | awk -F: '{print $1}'`
nv_line1=$(((nv_line+1)))
sed -i "${nv_line},${nv_line1}d" release.yaml

nvcrd_line=`grep neuvector-crd: release.yaml -n | awk -F: '{print $1}'`
nvcrd_line1=$(((nvcrd_line+1)))
sed -i "${nvcrd_line},${nvcrd_line1}d" release.yaml
}

#replace_version 
#if [ `grep neuvector-monitor release.yaml | wc -l` -ge "1" ]; then
#        echo 1
#  nv_line=`grep neuvector-moitor: release.yaml -n | awk -F: '{print $1}'`
#  number_release=$(((nvcrd_line-nv_line-1)))
#  nv_line1=$(((nv_line+$number_release)))
#  sed -i "${nv_line1}a - ${_CHART_VER_}+up${_MONITOR_VER_}" release.yaml
#elif [ `grep neuvector-monitor release.yaml | wc -l` == "0" ]; then
#        echo 2
#  t_line=`wc -l release.yaml | awk '{print $1}'`
#  sed -i  "${t_line}a neuvector-monitor:" release.yaml
#  t_line=`wc -l release.yaml | awk '{print $1}'`
#  sed -i  "${t_line}a - ${_CHART_VER_}+up${_MONITOR_VER_}" release.yaml
#fi

make clean

### Checking in patch
function commit_chart {
git add .
git commit -m "Add NeuVector Monitor chart version $_MONITOR_VER_"

git push --set-upstream origin $_NVBRANCH_


make charts

cd $_CHART_DIR_



git add .
git commit -m "make chart"
git push --set-upstream origin $_NVBRANCH_


#make validate
}
commit_chart 


### Updating release.yaml as 3rd commit`

function commit_releaseyaml {
  if [ `grep neuvector release.yaml | wc -l` -gt "1" ]; then
          echo 1
    nv_line=`grep neuvector: release.yaml -n | awk -F: '{print $1}'`
    nvcrd_line=`grep neuvector-crd: release.yaml -n | awk -F: '{print $1}'`
    number_release=$(((nvcrd_line-nv_line-1)))
    nv_line1=$(((nv_line+$number_release)))
    sed -i "${nv_line1}a\ \ - ${_CHART_VER_}+up${_MONITOR_VER_}" release.yaml
    nvcrd_line=`grep neuvector-crd: release.yaml -n | awk -F: '{print $1}'`
    nvcrd_line1=$(((nvcrd_line+$number_release)))
    sed -i "${nvcrd_line1}a\ \ - ${_CHART_VER_}+up${_MONITOR_VER_}" release.yaml
  elif [ `grep neuvector release.yaml | wc -l` == "0" ]; then
          echo 2
#    t_line=`wc -l release.yaml | awk '{print $1}'`
#    sed -i  "${t_line}a neuvector-monitor:" release.yaml
#    t_line=`wc -l release.yaml | awk '{print $1}'`
#    sed -i  "${t_line}a\ \ - ${_CHART_VER_}+up${_MONITOR_VER_}" release.yaml
     h_line=`grep harvester release.yaml -n | awk -F: '{print $1}'`
     nv_line=$(((h_line+1)))
     sed -i  "${nv_line}a neuvector-monitor:" release.yaml
     nv_line=$(((h_line+2)))
     sed -i  "${nv_line}a\ \ - ${_CHART_VER_}+up${_MONITOR_VER_}" release.yaml
  fi
  if [ `cat release.yaml|wc -l` == "0" ];then
    echo "neuvector-monitor:" > release.yaml
    echo "  - ${_CHART_VER_}+up${_MONITOR_VER_}" >> release.yaml
  fi

  git add release.yaml
  git commit -m "Update release.yaml"
  git push
}
commit_releaseyaml

