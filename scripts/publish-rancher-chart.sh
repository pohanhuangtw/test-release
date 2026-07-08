#!/bin/bash
##################### Update upstream NeuVector helm as per rancher chart requirement ##########
# get current version 
# curl -k -L  https://raw.githubusercontent.com/rancher/charts/refs/heads/release-v2.10/index.yaml |yq .entries.neuvector[].version |head -n1
# curl -k -L  https://raw.githubusercontent.com/rancher/charts/refs/heads/release-v2.9/index.yaml |yq .entries.neuvector[].version |head -n1
# curl -k -L  https://raw.githubusercontent.com/rancher/charts/refs/heads/release-v2.8/index.yaml |yq .entries.neuvector[].version |head -n1
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
_QLOC_=https://raw.githubusercontent.com/neuvector/misc/rancher/main/questions.yaml
_APPLOC_=https://raw.githubusercontent.com/neuvector/misc/rancher/main/app-readme.md



_FIRST_DIGIT_=`echo $_CHART_VER_ | awk -F. '{print $1}'`

if [ $_FIRST_DIGIT_ = "103" ];then
  _RANCHER_VERSION_=2.8.0-0
  _RANCHER_VERSION1_=2.9.0-0
  _NVBRANCH_=neuvector-dev-v2.8
  _RBRANCH_=dev-v2.8
elif [ $_FIRST_DIGIT_ = "104" ];then
  _RANCHER_VERSION_=2.9.0-0
  _RANCHER_VERSION1_=2.10.0-0
  _NVBRANCH_=neuvector-dev-v2.9
  _RBRANCH_=dev-v2.9
elif [ $_FIRST_DIGIT_ = "105" ];then
  _RANCHER_VERSION_=2.10.0-0
  _RANCHER_VERSION1_=2.11.0-0
  _NVBRANCH_=neuvector-dev-v2.10
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



_WORKING_DIR_=/tmp/rancher/helm

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
helm fetch neuvector/core --devel
helm fetch neuvector/crd --devel
_CORE_VER_=`helm search repo --devel | grep neuvector/core | awk '{print $2}'`
_CRD_VER_=`helm search repo --devel| grep neuvector/crd | awk '{print $2}'`


tar zxf core-${_CORE_VER_}.tgz
tar zxf crd-${_CORE_VER_}.tgz

cd $_WORKING_DIR_/core
#Removing rm values.schema.json
rm values.schema.json

#Updating Chart.yaml
echo "Core Updating Chart"
cat > .Chart.yaml << EOF
annotations:
  catalog.cattle.io/certified: rancher
  catalog.cattle.io/display-name: NeuVector
  catalog.cattle.io/kube-version: '>=1.18.0-0 < 1.32.0-0'
  catalog.cattle.io/namespace: cattle-neuvector-system
  catalog.cattle.io/os: linux
  catalog.cattle.io/permits-os: linux
  catalog.cattle.io/rancher-version: '>= start < end'
  catalog.cattle.io/auto-install: neuvector-crd=match
  catalog.cattle.io/provides-gvr: neuvector.com/v1
  catalog.cattle.io/release-name: neuvector
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
sed -i 's/name: core/name: neuvector/' .Chart.yaml
sed -i  /engine/d .Chart.yaml
sed -i "/version: $_CORE_VER_/i sources:\n- https://github.com/neuvector/neuvector"  .Chart.yaml
sed -i "s/_VER_/$_CORE_VER_/" .Chart.yaml
sed -i "s/description: Helm chart for NeuVector's core services/description: Helm feature chart for NeuVector container security platform./" .Chart.yaml
mv .Chart.yaml Chart.yaml
wget $_QLOC_
wget $_APPLOC_

VALUE_LINK="https://github.com/neuvector/neuvector-helm/tree/$_CORE_VER_/charts/core/values.yaml"
#sed -i 's|(values.yaml)|(https://github.com/neuvector/neuvector-helm/tree/2.2.2/charts/core/values.yaml)|' README.md
sed -i "s|(values.yaml)|($VALUE_LINK)|" README.md
sed -i /Contact/d README.md
sed -i '/## CRD/,/^$/d' README.md

_TAG_=`grep ^tag: values.yaml | awk '{print $2}'`

#_TAG_='5.0.0-b1'
cp values.yaml .values.yaml

echo "Core Updating values"
sed -i 's/registry: registry.neuvector.com/registry: docker.io/' .values.yaml
# commented below line to support 5.3 pre5.3 variable
#sed -i "/^tag: /d" .values.yaml
sed -i "/^psp/d" .values.yaml
sed -i "/^imagePullSecrets:/d" .values.yaml
sed -i 's/^serviceAccount: default/serviceAccount: neuvector/' .values.yaml

echo "Core Updating images in values"
sed -i "/    repository: neuvector\/controller/a \ \ \ \ tag: $_TAG_" .values.yaml
sed -i 's|repository: neuvector/controller|repository: rancher/neuvector-controller|' .values.yaml
sed -i 's|repository: neuvector/compliance-config|repository: rancher/neuvector-compliance-config|' .values.yaml
sso_line_number=`sed -n '/ranchersso/=' .values.yaml`
sso_line_number_plus=$((( sso_line_number + 1)))
sed -i "${sso_line_number_plus}s|enabled: false|enabled: true|" .values.yaml
sed -i "/    repository: neuvector\/enforcer/a \ \ \ \ tag: $_TAG_" .values.yaml
sed -i 's|repository: neuvector/enforcer|repository: rancher/neuvector-enforcer|' .values.yaml
sed -i "/    repository: neuvector\/manager/a \ \ \ \ tag: $_TAG_" .values.yaml
sed -i 's|repository: neuvector/manager|repository: rancher/neuvector-manager|' .values.yaml
sed -i 's|repository: neuvector/scanner|repository: rancher/neuvector-scanner|' .values.yaml
sed -i 's|repository: neuvector/updater|repository: rancher/neuvector-updater|' .values.yaml
sed -i 's|repository: neuvector/registry-adapter|repository: rancher/neuvector-registry-adapter|' .values.yaml
sed -i "/    url:/a \ \ \ \ \ \ enabled: false # PSP enablement should default to false" .values.yaml
sed -i "/    url:/a \ \ \ \ psp:" .values.yaml
sed -i "/    url:/a \ \ \ \ systemDefaultRegistry: \"\""  .values.yaml
sed -E -i 's/(leastPrivilege: false)/\1\n/' .values.yaml 

#deleting cloud related values
azure_line_number=`sed -n '/azure:/=' .values.yaml`
bootstrapPassword_line_number=`sed -n '/bootstrapPassword:/=' .values.yaml`
cloud_end_line_number=$((( bootstrapPassword_line_number - 2)))
sed -i "${azure_line_number},${cloud_end_line_number}d" .values.yaml
_PRIME_LINE_=`grep prime .values.yaml -n | awk -F: '{print $1}'`
_PRIME_LINE_1_=$(((_PRIME_LINE_+1)))
sed -i "${_PRIME_LINE_1_},${_PRIME_LINE_1_}s/enabled: false/enabled: true/" .values.yaml

mv .values.yaml values.yaml


#Updating templates
echo "Core Updating Template"

cd $_WORKING_DIR_/core/templates

#sed -i 's|image: "{{ .Values.registry }}/{{ .Values.controller.image.repository }}:{{ .Values.tag }}"|image: {{ template "system_default_registry" . }}{{ .Values.controller.image.repository }}:{{ .Values.controller.image.tag }}|' controller-deployment.yaml
# change controller image only becasue upstream changed, used include function
sed -i 's/image: {{ include "neuvector.controller.image" . | quote }}/image: {{ template "system_default_registry" . }}{{ .Values.controller.image.repository }}:{{ .Values.controller.image.tag }}/' controller-deployment.yaml
sed -i 's|image: "{{ .Values.registry }}/{{ .Values.enforcer.image.repository }}:{{ .Values.tag }}"|image: {{ template "system_default_registry" . }}{{ .Values.enforcer.image.repository }}:{{ .Values.enforcer.image.tag }}|' enforcer-daemonset.yaml
sed -i 's|image: "{{ .Values.registry }}/{{ .Values.manager.image.repository }}:{{ .Values.tag }}"|image: {{ template "system_default_registry" . }}{{ .Values.manager.image.repository }}:{{ .Values.manager.image.tag }}|' manager-deployment.yaml
sed -i 's|image: "{{ .Values.registry }}/{{ .Values.cve.scanner.image.repository }}:{{ .Values.cve.scanner.image.tag }}"|image: {{ template "system_default_registry" . }}{{ .Values.cve.scanner.image.repository }}:{{ .Values.cve.scanner.image.tag }}|' scanner-deployment.yaml
sed -i 's|image: "{{ .Values.registry }}/{{ .Values.cve.updater.image.repository }}:{{ .Values.cve.updater.image.tag }}"|image: {{ template "system_default_registry" . }}{{ .Values.cve.updater.image.repository }}:{{ .Values.cve.updater.image.tag }}|' updater-cronjob.yaml
sed -i 's|image: "{{ .Values.registry }}/{{ .Values.cve.adapter.image.repository }}:{{ .Values.cve.adapter.image.tag }}"|image: {{ template "system_default_registry" . }}{{ .Values.cve.adapter.image.repository }}:{{ .Values.cve.adapter.image.tag }}|' registry-adapter.yaml
sed -i 's|image: "{{ .Values.registry }}/{{ .Values.controller.prime.image.repository }}:{{ .Values.tag }}"|image: {{ template "system_default_registry" . }}{{ .Values.controller.prime.image.repository }}:{{ .Values.controller.prime.image.tag }}|' controller-deployment.yaml

#removing aws relate config from bootstrapsecret.yaml

sed  -i 3,5d bootstrap-secret.yaml


#Update NOTES.txt

aws_line_number=`sed -n '/aws.enabled/=' NOTES.txt`
sed -i "${aws_line_number},\$d" NOTES.txt

#Removing csp bootstrap-secret related files

rm csp-clusterrolebinding.yaml csp-clusterrole.yaml csp-crd.yaml csp-deployment.yaml csp-rolebinding.yaml csp-role.yaml csp-serviceaccount.yaml 

#rm bootstrap-secret.yaml

#Adding psp check
cat > validate-psp-install.yaml << EOF
{{- if gt (len (lookup "rbac.authorization.k8s.io/v1" "ClusterRole" "" "")) 0 -}}
{{- if .Values.global.cattle.psp.enabled }}
{{- if not (.Capabilities.APIVersions.Has "policy/v1beta1/PodSecurityPolicy") }}
{{- fail "The target cluster does not have the PodSecurityPolicy API resource. Please disable PSPs in this chart before proceeding." -}}
{{- end }}
{{- end }}
{{- end }}
EOF

#Changing psp template according Rancher requirement
sed -i 's/Values.psp/Values.global.cattle.psp.enabled/' psp.yaml

#Changing oem data in deployment and ds filea under template directory only for certified operator
#remove controller deployment because include function for image
#for file in controller-deployment.yaml enforcer-daemonset.yaml manager-deployment.yaml scanner-deployment.yaml updater-cronjob.yaml
for file in enforcer-daemonset.yaml manager-deployment.yaml scanner-deployment.yaml updater-cronjob.yaml
do
#  cp ~/scripts/operator/certified/container_image/v0.1.3/helm-charts/neuvector/core/templates/$file .
  if [ $file == "controller-deployment.yaml" -o $file == "enforcer-daemonset.yaml" ];then
     endline="securityContext"
  elif [ $file == "manager-deployment.yaml" ];then
     endline="ports"
  else
     endline="imagePullPolicy"
  fi
  if [  $file == "enforcer-daemonset.yaml" -o $file == "manager-deployment.yaml" ];then
    start_line_del_number=`sed -n '/registry.neuvector.com/=' $file`
    end_line_del_number=$(((start_line_del_number + 9)))
    sed -i "${start_line_del_number},${end_line_del_number}d" $file
    start_line_del_number=`sed -n "/$endline/=" $file | head -n 1`
    end_line_del_number=$(((start_line_del_number - 2)))
    end_line_del_number1=$(((start_line_del_number - 1)))
    sed -i "${end_line_del_number},${end_line_del_number1}d" $file
  elif [ $file == "controller-deployment.yaml" ];then
    start_line_del_number=`sed -n '/registry.neuvector.com/=' $file`
    end_line_del_number=$(((start_line_del_number + 9)))
    sed -i "${start_line_del_number},${end_line_del_number}d" $file
    start_line_del_number=`sed -n "/$endline/=" $file | head -n 1`
    end_line_del_number=$(((start_line_del_number - 3)))
    end_line_del_number1=$(((start_line_del_number - 2)))
    sed -i "${end_line_del_number},${end_line_del_number1}d" $file
  else
    start_line_del_number=`sed -n '/registry.neuvector.com/=' $file`
    end_line_del_number=$(((start_line_del_number + 11)))
    sed -i "${start_line_del_number},${end_line_del_number}d" $file
    start_line_del_number=`sed -n "/$endline/=" $file | head -n 1`
    end_line_del_number=$(((start_line_del_number - 2)))
    end_line_del_number1=$(((start_line_del_number - 1)))
    sed -i "${end_line_del_number},${end_line_del_number1}d" $file
  fi
done

#remove cloud related changes



#for file in controller-deployment.yaml enforcer-daemonset.yaml manager-deployment.yaml scanner-deployment.yaml
for file in enforcer-daemonset.yaml manager-deployment.yaml scanner-deployment.yaml
do
#  cp ~/scripts/operator/certified/container_image/v0.1.3/helm-charts/neuvector/core/templates/$file .
  if [ $file == "controller-deployment.yaml" -o $file == "enforcer-daemonset.yaml" ];then
     endline="securityContext"
  elif [ $file == "manager-deployment.yaml" ];then
     endline="ports"
  else
     endline="imagePullPolicy"
  fi
  if [ $file == "controller-deployment.yaml" ];then
    start_line_del_number=`sed -n "/azure.enabled/=" $file | head -n1`
    end_line_del_number=$(((start_line_del_number + 2)))
    sed -i "${start_line_del_number},${end_line_del_number}d" $file
    start_line_del_number=`sed -n "/$endline/=" $file | head -n 1`
    end_line_del_number=$(((start_line_del_number - 2)))
    sed -i "${end_line_del_number}d" $file
  else
    start_line_del_number=`sed -n "/azure.enabled/=" $file | head -n1`
    end_line_del_number=$(((start_line_del_number + 2)))
    sed -i "${start_line_del_number},${end_line_del_number}d" $file
    start_line_del_number=`sed -n "/$endline/=" $file | head -n 1`
    end_line_del_number=$(((start_line_del_number - 1)))
    sed -i "${end_line_del_number}d" $file
  fi
done

#disabling aws in controller deployment
start_line_del_number=`sed -n /aws.enabled/= controller-deployment.yaml | head -n1`
end_line_del_number=$(((start_line_del_number + 11)))
sed -i "${start_line_del_number},${end_line_del_number}d" controller-deployment.yaml

#remove define for controller image
define_image__line_number=`sed -n '/neuvector.controller.image/=' _helpers.tpl`
sed -i "${define_image__line_number},\$d" _helpers.tpl

#add define for controller image

cat > .helper << EOF

{{- define "neuvector.controller.image" -}}
{{- printf "%s/%s:%s" .Values.registry .Values.controller.image.repository .Values.tag }}
{{- end -}}

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


#Updating CRD files
echo "CRD Updating Chart"

cd $_WORKING_DIR_/crd

cat > .Chart.yaml << EOF
annotations:
  catalog.cattle.io/release-name: neuvector-crd
  catalog.cattle.io/namespace: cattle-neuvector-system
  catalog.cattle.io/certified: rancher
  catalog.cattle.io/hidden: true
EOF
echo "type: application" >> Chart.yaml
cat Chart.yaml >> .Chart.yaml
sed -i 's/name: crd/name: neuvector-crd/' .Chart.yaml
sed -i  /engine/d .Chart.yaml
mv .Chart.yaml Chart.yaml
cp values.yaml .values.yaml
echo "  enabled: true" >> .values.yaml
sed -i 's/^serviceAccount: default/serviceAccount: neuvector/' .values.yaml
mv .values.yaml values.yaml



export PACKAGE=neuvector
_CHART_DIR_=$CHART_DIR
_NV_PKG_DIR_=$CHART_DIR/packages/neuvector
_NV_HELM_CHART_DIR_=/tmp/rancher/helm/

# To remove unreleased version chart execute function if needed

function remove_chart {
  cd $_CHART_DIR_
  make remove CHART=neuvector VERSION=101.0.2+up2.4.0
  git add .
  git commit -m "Remove charts/assets for neuvector 101.0.2+up2.4.0"
  git push --set-upstream origin $_NVBRANCH_
  make remove CHART=neuvector-crd VERSION=101.0.2+up2.4.0
  git add .
  git commit -m "Remove charts/assets for neuvector-crd 101.0.2+up2.4.0"
  git push --set-upstream origin $_NVBRANCH_
}


_CORE_VER_=`helm search repo --devel | grep neuvector/core | awk '{print $2}'`
_CRD_VER_=`helm search repo --devel | grep neuvector/crd | awk '{print $2}'`

echo "Rancher Chart directory: $_CHART_DIR_"  
echo "NeuvectorPackage directory: $_NV_PKG_DIR_" 
echo "Neuvector Helm Directory: $_NV_HELM_CHART_DIR_" 
echo "Neuvector Helm Core Version: $_CORE_VER_" 
echo "Neuvector Helm CRD Version: $_CRD_VER_"

echo -n "Provide Neuvector Rancher Chart Version:"
_CHART_VER_=$1
echo "Neuvector Rancher Chart Version: $_CHART_VER_"

#Create dir 
if [ ! -d $_NV_PKG_DIR_ ]; then
  echo "Creating directory"
  mkdir $_NV_PKG_DIR_
fi

cd $_NV_PKG_DIR_

git checkout $_NVBRANCH_

#cp $_NV_HELM_CHART_DIR_/neuvector/package-no-addchart.yaml $_NV_PKG_DIR_/package.yaml

cat > $_NV_PKG_DIR_/package.yaml << EOF
url: https://neuvector.github.io/neuvector-helm/core-VER.tgz
version: _CHART_VER_
EOF

sed -i "1s/VER/$_CORE_VER_/" $_NV_PKG_DIR_/package.yaml 
sed -i "s/_CHART_VER_/${_CHART_VER_}/" $_NV_PKG_DIR_/package.yaml 

### Change to main chart

cd $_CHART_DIR_
rm -rf $_NV_PKG_DIR_/templates/
rm -rf $_NV_PKG_DIR_/generated-changes/


make prepare
#find $_NV_PKG_DIR_

mkdir $_NV_PKG_DIR_/charts/crds
mv $_NV_PKG_DIR_/charts/templates/crd.yaml  $_NV_PKG_DIR_/charts/crds
#cp $_NV_HELM_CHART_DIR_/crd/templates/_helpers.tpl $_NV_PKG_DIR_/charts/crds
cp $_NV_HELM_CHART_DIR_/core/* $_NV_PKG_DIR_/charts/
cp $_NV_HELM_CHART_DIR_/core/templates/* $_NV_PKG_DIR_/charts/templates/
rm $_NV_PKG_DIR_/charts/values.schema.json
rm $_NV_PKG_DIR_/charts/templates/crd.yaml
rm $_NV_PKG_DIR_/charts/templates/csp-*
#rm $_NV_PKG_DIR_/charts/templates/bootstrap-secret.yaml
make patch

mkdir -p $_NV_PKG_DIR_/templates/crd-template

cp $_NV_HELM_CHART_DIR_/crd/Chart.yaml $_NV_PKG_DIR_/templates/crd-template/
cp $_NV_HELM_CHART_DIR_/crd/README.md $_NV_PKG_DIR_/templates/crd-template/
cp $_NV_HELM_CHART_DIR_/crd/values.yaml $_NV_PKG_DIR_/templates/crd-template/
#cp $_NV_HELM_CHART_DIR_/neuvector/package-addchart.yaml $_NV_PKG_DIR_/package.yaml

cat > $_NV_PKG_DIR_/package.yaml << EOF
url: https://neuvector.github.io/neuvector-helm/core-VER.tgz
version: _CHART_VER_
additionalCharts:
- workingDir: charts-crd
  crdOptions:
    templateDirectory: crd-template
    crdDirectory: templates
EOF

sed -i "s/_CHART_VER_/$_CHART_VER_/" $_NV_PKG_DIR_/package.yaml 
sed -i "1s/VER/$_CORE_VER_/" $_NV_PKG_DIR_/package.yaml


cp $_NV_HELM_CHART_DIR_/crd/templates/_helpers.tpl $_NV_PKG_DIR_/generated-changes/overlay/crds/

cd $_CHART_DIR_

function replace_version {

nv_line=`grep neuvector: release.yaml -n | awk -F: '{print $1}'`
nv_line1=$(((nv_line+1)))
sed -i "${nv_line},${nv_line1}d" release.yaml

nvcrd_line=`grep neuvector-crd: release.yaml -n | awk -F: '{print $1}'`
nvcrd_line1=$(((nvcrd_line+1)))
sed -i "${nvcrd_line},${nvcrd_line1}d" release.yaml
}

#replace_version 

#cat > .release.yaml << EOF
#neuvector:
#- _CHART_VER_+up_CORE_VER_
#neuvector-crd:
#- _CHART_VER_+up_CORE_VER_
#EOF

#sed -i "s/_CHART_VER_/$_CHART_VER_/" .release.yaml
#sed -i "s/_CORE_VER_/$_CORE_VER_/" .release.yaml

#cat .release.yaml >> release.yaml
#rm .release.yaml

make prepare

#cp $_NV_HELM_CHART_DIR_/crd/templates/_helpers.tpl  $_NV_PKG_DIR_/charts-crd/templates/
### Patching charts


#make patch

#find $_NV_PKG_DIR_
make clean
#find $_NV_PKG_DIR_

### Checking in patch
function commit_chart {
git add .
git commit -m "Add NeuVector chart version $_CORE_VER_"
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
    sed -i "${nv_line1}a\ \ - ${_CHART_VER_}+up${_CORE_VER_}" release.yaml
    nvcrd_line=`grep neuvector-crd: release.yaml -n | awk -F: '{print $1}'`
    nvcrd_line1=$(((nvcrd_line+$number_release)))
    sed -i "${nvcrd_line1}a\ \ - ${_CHART_VER_}+up${_CORE_VER_}" release.yaml
  elif [ `grep neuvector release.yaml | wc -l` == "0" ]; then
          echo 2
    t_line=`wc -l release.yaml | awk '{print $1}'`
    sed -i  "${t_line}a neuvector:" release.yaml
    t_line=`wc -l release.yaml | awk '{print $1}'`
    sed -i  "${t_line}a\ \ - ${_CHART_VER_}+up${_CORE_VER_}" release.yaml
    t_line=`wc -l release.yaml | awk '{print $1}'`
    sed -i  "${t_line}a neuvector-crd:" release.yaml
    t_line=`wc -l release.yaml | awk '{print $1}'`
    sed -i  "${t_line}a\ \ - ${_CHART_VER_}+up${_CORE_VER_}" release.yaml
  fi
  
  git add release.yaml
  git commit -m "Update release.yaml"
  git push --set-upstream origin $_NVBRANCH_
}

commit_releaseyaml
