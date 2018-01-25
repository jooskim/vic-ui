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
    echo "Usage: $0 --vcip vc_ip --ovaip vic_appliance_ip "
    exit 1
}

if [ -z $BUILD_NUMBER ] ; then
    BUILD_NUMBER=0
fi

#TAG_NUM=$(git describe --tags $(git rev-list --tags --max-count=1) | cut -c 2- | sed -e 's/\(-rc[[:digit:]]\)//' -e 's/\(-dev\)$//')
ARGS=$(getopt --options "" --longoptions "ovaip:vcip:plugin:" -- "$@")

while true ; do
    case $1 in
        --ovaip)
            PRODUCT_VM_IP=$2
            shift
            ;;
        --vcip)
            VC_IP=$2
            shift
            ;;
        --plugin)
            PLUGIN_FOLDERNAME=$2
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            break
            ;;
    esac
    shift
done

if [ -z $PRODUCT_VM_IP ] ; then
    echo "No IP was provided for the VIC Product appliance!"
    exit 1
fi

if [ -z $VC_IP ] ; then
    echo "No IP was provided for the vCenter Server appliance!"
    exit 1
fi

if [ -z $PLUGIN_FOLDERNAME ] ; then
    echo "Please provide the plugin folder name. e.g. com.vmware.vic-v${UI_VERSION}"
    exit 1
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
zip -9r ../new-vic-service.jar ./
cd ../ && rm -rf tmp vic-service.jar && mv new-vic-service.jar vic-service.jar

# cd .. to com.vmware.vic-v${UI_VERSION}.$BUILD_NUMBER and rezip the contents
cd ../ && zip -9r "../com.vmware.vic-v${UI_VERSION}.$BUILD_NUMBER.zip" ./

# all contents are now up to date. scp it to the OVA appliance
nc -vz $PRODUCT_VM_IP 443

# cd back to where we were
cd $CURRENT_WORKING_DIR