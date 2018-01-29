#!/bin/bash -e
# Copyright 2018 VMware, Inc. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# 1. rename the version string to be: ${UI_VERSION}.${BUILD_NUMBER} for vSphere Client
# 2. rename the version string in $(VICUI_H5_SERVICE_PATH)/src/main/resources/configs.properties
# 3. rezip the plugin contents
# 3. upload the zip to the $PRODUCT_VM_IP:/opt/vmware/fileserver/files/
# 4. force install the plugin on the target VC

UI_VERSION="0.0.1"
CURRENT_WORKING_DIR=$(pwd)
SCRIPTS_DIR=$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)

show_error() {
    echo "Usage: $0 -v vc_ip -o vic_appliance_ip -p plugin_folder"
    exit 1
}

if [ -z $BUILD_NUMBER ] ; then
    BUILD_NUMBER=0
fi

#TAG_NUM=$(git describe --tags $(git rev-list --tags --max-count=1) | cut -c 2- | sed -e 's/\(-rc[[:digit:]]\)//' -e 's/\(-dev\)$//')

while getopts :o:v:p: flag ; do
    case $flag in
        o)
            PRODUCT_VM_IP=$OPTARG
            ;;
        v)
            VC_IP=$OPTARG
            ;;
        p)
            PLUGIN_FOLDERNAME=$OPTARG
            ;;
        \?)
            show_error
            ;;
        *)
            show_error
            ;;
    esac
done

if [ -z $PRODUCT_VM_IP ] ; then
    echo "No IP was provided for the VIC Product appliance!"
    show_error
fi

if [ -z $VC_IP ] ; then
    echo "No IP was provided for the vCenter Server appliance!"
    show_error
fi

if [ -z $PLUGIN_FOLDERNAME ] ; then
    echo "Please provide the plugin folder name. e.g. com.vmware.vic-v${UI_VERSION}"
    show_error
fi

NEW_PLUGIN_PATH="$SCRIPTS_DIR/plugin-packages/com.vmware.vic-v${UI_VERSION}.$BUILD_NUMBER"

if [ ! -d $SCRIPTS_DIR/plugin-packages/$PLUGIN_FOLDERNAME ] ; then
    ls -la $SCRIPTS_DIR/plugin-packages/$PLUGIN_FOLDERNAME
    echo "The plugin was not found in $SCRIPTS_DIR/plugin-packages/$PLUGIN_FOLDERNAME!!"
    exit 1
fi

# make a duplicate
cp -rf "$SCRIPTS_DIR/plugin-packages/$PLUGIN_FOLDERNAME" "$NEW_PLUGIN_PATH"

# update plugin-package.xml so that the version comforms to the following format:
# v${UI_VERSION}.$BUILD_NUMBER
cd $NEW_PLUGIN_PATH
sed -e "s/vic\" version=.*$/vic\" ver=\"${UI_VERSION}.$BUILD_NUMBER\" type=\"html\" name=\"vSphere Integrated Containers\"/" plugin-package.xml > plugin-package-new.xml
rm plugin-package.xml
mv plugin-package-new.xml plugin-package.xml

# update configs.properties in vic-service.jar
cd plugins
unzip -od ./tmp vic-service.jar
echo "uiVersion=v${UI_VERSION}.$BUILD_NUMBER - ${COMMIT_URL}" > ./tmp/configs.properties
cd tmp
zip -9r ../new-vic-service.jar ./ >/dev/null
cd ../ && rm -rf tmp vic-service.jar && mv new-vic-service.jar vic-service.jar

# cd .. to com.vmware.vic-v${UI_VERSION}.$BUILD_NUMBER and rezip the contents
NEW_PLUGIN_ZIP="com.vmware.vic-v${UI_VERSION}.$BUILD_NUMBER.zip"
cd ../ && zip -9r "../$NEW_PLUGIN_ZIP" ./ >/dev/null

# all contents are now updated. scp it to the OVA appliance
nc -vz $PRODUCT_VM_IP 22 >/dev/null 2>/dev/null
PRODUCT_VM_REACHABLE=$?

if [ $PRODUCT_VM_REACHABLE -gt 0 ] ; then
    echo "VIC Appliance was not found at $PRODUCT_VM_IP!"
    exit 1
fi

# scp the plugin zip file to ${PRODUCT_VM_IP}
sshpass -p 'Admin!23' scp -o StrictHostKeyChecking=no -r ../com.vmware.vic-v${UI_VERSION}.$BUILD_NUMBER.zip root@${PRODUCT_VM_IP}:/opt/vmware/fileserver/files/

# register the plugin with the VC testbed at $VC_IP
VC_FINGERPRINT="$(echo -n | openssl s_client -connect $VC_IP:443 2>/dev/null | openssl x509 -fingerprint -noout -sha1 | cut -d = -f 2)"
APPLIANCE_FINGERPRINT="$(echo -n | openssl s_client -connect $PRODUCT_VM_IP:9443 2>/dev/null | openssl x509 -fingerprint -noout -sha1 | cut -d = -f 2)" # does not work on macOS for this VM

echo VC FINGERPRINT: $VC_FINGERPRINT
echo APPLIANCE_FINGERPRINT: $APPLIANCE_FINGERPRINT

# download https://storage.googleapis.com/vic-engine-builds/vic_15800.tar.gz and get vic-ui-linux ready
VIC_UI_BINARY_ROOT="/tmp/vic_15800"
VIC_UI_LINUX_BIN="$VIC_UI_BINARY_ROOT/vic-ui-linux"
mkdir -p $VIC_UI_BINARY_ROOT

if [ ! -f $VIC_UI_LINUX_BIN ] ; then
    echo
    echo vic engine 15800 was not found. downloading...
    curl -k https://storage.googleapis.com/vic-engine-builds/vic_15800.tar.gz -o $VIC_UI_BINARY_ROOT.tar.gz 2>/dev/null
    tar -xvf $VIC_UI_BINARY_ROOT.tar.gz -C $VIC_UI_BINARY_ROOT --strip 1

fi

# register the plugin with vCenter Server
$VIC_UI_LINUX_BIN install \
    --target $VC_IP \
    --user administrator@vsphere.local \
    --password 'Admin!23' \
    --thumbprint $VC_FINGERPRINT \
    --force \
    --configure-ova \
    --type=VicApplianceVM \
    --company VMware \
    --key com.vmware.vic \
    --name "vSphere Integrated Containers UI Plugin" \
    --summary E2E \
    --server-thumbprint $APPLIANCE_FINGERPRINT \
    --version ${UI_VERSION}.$BUILD_NUMBER \
    --url https://${PRODUCT_VM_IP}:9443/files/$NEW_PLUGIN_ZIP

# restart the vSphere Client service
sshpass -p 'vmware' ssh -o StrictHostKeyChecking=no root@${VC_IP} "service-control --stop vsphere-ui && service-control --start vsphere-ui"

# cd back to where we were
cd $CURRENT_WORKING_DIR
echo Done registering the plugin with VC. Ready for E2E testing.
