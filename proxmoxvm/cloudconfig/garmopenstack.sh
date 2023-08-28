#!/bin/bash

set -e
set -o pipefail

if [ ! -t 0 ]
then
    INPUT=$(cat -)
fi
MYPATH=$(realpath ${BASH_SOURCE[0]})
MYDIR=$(dirname "${MYPATH}")
TEMPLATES="$MYDIR/cloudconfig"

# Defaults
# set this variable to 0 in the provider config to disable.
BOOT_FROM_VOLUME=${BOOT_FROM_VOLUME:-1}

# END Defaults

if [ -z "$GARM_PROVIDER_CONFIG_FILE" ]
then
    echo "no config file specified in env"
    exit 1
fi

source "$GARM_PROVIDER_CONFIG_FILE"

declare -A OS_TO_GH_ARCH_MAP
OS_TO_GH_ARCH_MAP["x86_64"]="x64"
OS_TO_GH_ARCH_MAP["armv7l"]="arm64"
OS_TO_GH_ARCH_MAP["mips64"]="arm64"
OS_TO_GH_ARCH_MAP["mips64el"]="arm64"
OS_TO_GH_ARCH_MAP["mips"]="arm"
OS_TO_GH_ARCH_MAP["mipsel"]="arm"

declare -A OS_TO_GARM_ARCH_MAP
OS_TO_GARM_ARCH_MAP["x86_64"]="amd64"
OS_TO_GARM_ARCH_MAP["armv7l"]="arm64"
OS_TO_GARM_ARCH_MAP["mips64"]="arm64"
OS_TO_GARM_ARCH_MAP["mips64el"]="arm64"
OS_TO_GARM_ARCH_MAP["mips"]="arm"
OS_TO_GARM_ARCH_MAP["mipsel"]="arm"

declare -A GARM_TO_GH_ARCH_MAP
GARM_TO_GH_ARCH_MAP["amd64"]="x64"
GARM_TO_GH_ARCH_MAP["arm"]="arm"
GARM_TO_GH_ARCH_MAP["arm64"]="arm64"

declare -A STATUS_MAP
STATUS_MAP["ACTIVE"]="running"
STATUS_MAP["SHUTOFF"]="stopped"
STATUS_MAP["BUILD"]="pending_create"
STATUS_MAP["ERROR"]="error"
STATUS_MAP["DELETING"]="pending_delete"

function checkValNotNull() {
    if [ -z "$1" -o "$1" == "null" ];then
        echo "failed to fetch value $2"
        return 1
    fi
    return 0
}

function getOSImageDetails() {
    IMAGE_ID=$(echo "$INPUT" | jq -r -c '.image')
    OS_IMAGE=$(openstack image show "$IMAGE_ID" -f json)
    echo "$OS_IMAGE"
}

function getOpenStackNetworkID() {
    if [ -z "$OPENSTACK_PRIVATE_NETWORK" ]
    then
        echo "no network specified in config"
        return 1
    fi

    NET_ID=$(openstack network show ${OPENSTACK_PRIVATE_NETWORK} -f value -c id)
    if [ -z "$NET_ID" ];then
        echo "failed to find network $OPENSTACK_PRIVATE_NETWORK"
    fi
    echo ${NET_ID}
}

function getVolumeSizeFromFlavor() {
    local flavor="$1"

    FLAVOR_DETAILS=$(openstack flavor show "${flavor}" -f json)
    DISK_SIZE=$(echo "$FLAVOR_DETAILS" | jq -c -r '.disk')
    if [ -z "$DISK_SIZE" ];then
        echo "failed to get disk size from flavor"
        return 1
    fi

    echo ${DISK_SIZE}
}

function waitForVolume() {
    local volumeName=$1
    set +e
    status=$(openstack volume show "${volumeName}" -f json | jq -r -c '.status')
    if [ $? -ne 0 ];then
        CODE=$?
        set -e
        return $CODE
    fi
    set -e
    while [ "${status}" != "available" -a "${status}" != "error" ];do
        status=$(openstack volume show "${volumeName}" -f json | jq -r -c '.status')
    done
}

function createVolumeFromImage() {
    local image="$1"
    local disk_size="$2"
    local instance_name="$3"
    if [ -z ${image} -o -z ${disk_size} -o -z "${instance_name}" ];then
        echo "missing image, disk size or instance name in function call"
        return 1
    fi
    # Instance names contain a UUID. It should be safe to create a volume with the same name and
    # expect it to be unique.
    set +e
    VOLUME_INFO=$(openstack volume create -f json --image "${image}" --size "${disk_size}" "${instance_name}")
    if [ $? -ne 0 ]; then
        CODE=$?
        openstack volume delete "${instance_name}" || true
        set -e
        return $CODE
    fi
    waitForVolume "${instance_name}"
    echo "${VOLUME_INFO}"
}

function requestedArch() {
    ARCH=$(echo "$INPUT" | jq -c -r '.arch')
    checkValNotNull "${ARCH}" "arch" || return $?
    echo "${ARCH}"
}

function downloadURL() {
    [ -z "$1" -o -z "$2" ] && return 1
    GH_ARCH="${GARM_TO_GH_ARCH_MAP[$2]}"
    URL=$(echo "$INPUT" | jq -c -r --arg OS "$1" --arg ARCH "$GH_ARCH" '(.tools[] | select( .os == $OS and .architecture == $ARCH)).download_url')
    checkValNotNull "${URL}" "download URL" || return $?
    echo "${URL}"
}

function tempDownloadToken() {
    [ -z "$1" -o -z "$2" ] && return 1
    GH_ARCH="${GARM_TO_GH_ARCH_MAP[$2]}"
    TOKEN=$(echo "$INPUT" | jq -c -r --arg OS "$1" --arg ARCH "$GH_ARCH" '(.tools[] | select( .os == $OS and .architecture == $ARCH)).temp_download_token')
    echo "${TOKEN}"
}

function runnerTokenURL() {
    METADATA_URL=$(echo "$INPUT" | jq -c -r '."metadata-url"')
    checkValNotNull "${METADATA_URL}" "metadata-url" || return $?
    echo "${METADATA_URL}/runner-registration-token/"
}

function downloadFilename() {
    [ -z "$1" -o -z "$2" ] && return 1
    GH_ARCH="${GARM_TO_GH_ARCH_MAP[$2]}"
    FN=$(echo "$INPUT" | jq -c -r --arg OS "$1" --arg ARCH "$GH_ARCH" '(.tools[] | select( .os == $OS and .architecture == $ARCH)).filename')
    checkValNotNull "${FN}" "download filename" || return $?
    echo "${FN}"
}

function poolID() {
    POOL_ID=$(echo "$INPUT" | jq -c -r '.pool_id')
    checkValNotNull "${POOL_ID}" "pool_id" || return $?
    echo "${POOL_ID}"
}

function flavor() {
    FLAVOR=$(echo "$INPUT" | jq -c -r '.flavor')
    checkValNotNull "${FLAVOR}" "flavor" || return $?
    echo "${FLAVOR}"
}

function image() {
    IMG=$(echo "$INPUT" | jq -c -r '.image')
    checkValNotNull "${IMG}" "image" || return $?
    echo "${IMG}"
}

function repoURL() {
    REPO=$(echo "$INPUT" | jq -c -r '.repo_url')
    checkValNotNull "${REPO}" "repo_url" || return $?
    echo "${REPO}"
}

function callbackURL() {
    CB_URL=$(echo "$INPUT" | jq -c -r '."callback-url"')
    checkValNotNull "${CB_URL}" "callback-url" || return $?
    echo "${CB_URL}"
}

function callbackToken() {
    CB_TK=$(echo "$INPUT" | jq -c -r '."instance-token"')
    checkValNotNull "${CB_TK}" "instance-token" || return $?
    echo "${CB_TK}"
}

function instanceName() {
    NAME=$(echo "$INPUT" | jq -c -r '.name')
    checkValNotNull "${NAME}" "name" || return $?
    echo "${NAME}"
}

function labels() {
    LBL=$(echo "$INPUT" | jq -c -r '.labels | join(",")')
    checkValNotNull "${LBL}" "labels" || return $?
    echo "${LBL}"
}

function getCloudConfig() {
    IMAGE_DETAILS=$(getOSImageDetails)

    OS_TYPE=$(echo "${IMAGE_DETAILS}" | jq -c -r '.properties.os_type')
    checkValNotNull "${OS_TYPE}" "os_type" || return $?

    ARCH=$(requestedArch)
    DW_URL=$(downloadURL "${OS_TYPE}" "${ARCH}")
    DW_TOKEN=$(tempDownloadToken "${OS_TYPE}" "${ARCH}")
    DW_FILENAME=$(downloadFilename "${OS_TYPE}" "${ARCH}")
    LABELS=$(labels)

    TMP_SCRIPT=$(mktemp)
    TMP_CC=$(mktemp)

    INSTALL_TPL=$(cat "${TEMPLATES}/install_runner.tpl")
    CC_TPL=$(cat "${TEMPLATES}/userdata.tpl")
    echo "$INSTALL_TPL" | sed -e "s|GARM_CALLBACK_URL|$(callbackURL)|g" \
    -e "s|GARM_CALLBACK_TOKEN|$(callbackToken)|g" \
    -e "s|GH_DOWNLOAD_URL|${DW_URL}|g" \
    -e "s|GH_FILENAME|${DW_FILENAME}|g" \
    -e "s|GH_TARGET_URL|$(repoURL)|g" \
    -e "s|GARM_METADATA_URL|$(runnerTokenURL)|g" \
    -e "s|GH_RUNNER_NAME|$(instanceName)|g" \
    -e "s|GH_TEMP_DOWNLOAD_TOKEN|${DW_TOKEN}|g" \
    -e "s|GH_RUNNER_LABELS|${LABELS}|g" > ${TMP_SCRIPT}

    AS_B64=$(base64 -w0 ${TMP_SCRIPT})
    echo "${CC_TPL}" | sed "s|RUNNER_INSTALL_B64|${AS_B64}|g" > ${TMP_CC}
    echo "${TMP_CC}"
}

function waitForServer() {
    local srv_id="$1"

    srv_info=$(openstack server show -f json "${srv_id}")
    [ $? -ne 0 ] && return $?

    status=$(echo "${srv_info}" | jq -r -c '.status')

    while [ "${status}" != "ERROR" -a "${status}" != "ACTIVE" ];do
        sleep 0.5
        srv_info=$(openstack server show -f json "${srv_id}")
        [ $? -ne 0 ] && return $?
        status=$(echo "${srv_info}" | jq -r -c '.status')
    done
    echo "${srv_info}"
}

function CreateInstance() {
    if [ -z "$INPUT" ];then
        echo "expected build params in stdin"
        exit 1
    fi

    CC_FILE=$(getCloudConfig)
    FLAVOR=$(flavor)
    IMAGE=$(image)
    INSTANCE_NAME=$(instanceName)
    NET=$(getOpenStackNetworkID)
    IMAGE_DETAILS=$(getOSImageDetails)

    OS_TYPE=$(echo "${IMAGE_DETAILS}" | jq -c -r '.properties.os_type')
    checkValNotNull "${OS_TYPE}" "os_type" || return $?
    DISTRO=$(echo "${IMAGE_DETAILS}" | jq -c -r '.properties.os_distro')
    checkValNotNull "${DISTRO}" "os_distro" || return $?
    VERSION=$(echo "${IMAGE_DETAILS}" | jq -c -r '.properties.os_version')
    checkValNotNull "${VERSION}" "os_version" || return $?
    ARCH=$(echo "${IMAGE_DETAILS}" | jq -c -r '.properties.architecture')
    checkValNotNull "${ARCH}" "architecture" || return $?
    GH_ARCH=${OS_TO_GH_ARCH_MAP[${ARCH}]}

    if [ -z "${GH_ARCH}" ];then
        GH_ARCH=${ARCH}
    fi

    SOURCE_ARGS=""

    if [ "${BOOT_FROM_VOLUME}" -eq 1 ];then
        VOL_SIZE=$(getVolumeSizeFromFlavor "${FLAVOR}")
        VOL_INFO=$(createVolumeFromImage "${IMAGE}" "${VOL_SIZE}" "${INSTANCE_NAME}")
        if [ $? -ne 0 ];then
            openstack volume delete "${INSTANCE_NAME}" || true
        fi
        SOURCE_ARGS="--volume ${INSTANCE_NAME}"
    else
        SOURCE_ARGS="--image ${IMAGE}"
    fi

    set +e

    TAGS="--tag garm-controller-id=${GARM_CONTROLLER_ID} --tag garm-pool-id=${GARM_POOL_ID}"
    PROPERTIES="--property os_type=${OS_TYPE} --property os_name=${DISTRO} --property os_version=${VERSION} --property os_arch=${GH_ARCH} --property pool_id=${GARM_POOL_ID}"
    SRV_DETAILS=$(openstack server create --os-compute-api-version 2.52 ${SOURCE_ARGS} ${TAGS} ${PROPERTIES} --flavor "${FLAVOR}" --user-data="${CC_FILE}" --network="${NET}" "${INSTANCE_NAME}")
    if [ $? -ne 0 ];then
        openstack volume delete "${INSTANCE_NAME}" || true
        exit 1
    fi
    SRV_DETAILS=$(waitForServer "${INSTANCE_NAME}")
    if [ $? -ne 0 ];then
        CODE=$?
        # cleanup
        rm -f "${CC_FILE}" || true
        openstack server delete "${INSTANCE_NAME}" || true
        openstack volume delete "${INSTANCE_NAME}" || true
        set -e
        FAULT=$(echo "${SRV_DETAILS}"| jq -rc '.fault')
        echo "Failed to create server: ${FAULT}"
        exit $CODE
    fi
    set -e
    rm -f "${CC_FILE}" || true

    SRV_ID=$(echo "${SRV_DETAILS}" | jq -r -c '.id')
    STATUS=$(echo "${SRV_DETAILS}" | jq -r -c '.status')
    FAULT=$(echo "${SRV_DETAILS}" | jq -r -c '.fault')
    FAULT_VAL=""
    if [ ! -z "${FAULT}" -a "${FAULT}" != "null" ];then
        FAULT_VAL=$(echo "${FAULT}" | base64 -w0)
    fi

    jq -rnc \
        --arg PROVIDER_ID ${SRV_ID} \
        --arg NAME "${INSTANCE_NAME}" \
        --arg OS_TYPE "${OS_TYPE}" \
        --arg OS_NAME "${DISTRO}" \
        --arg OS_VERSION "${VERSION}" \
        --arg ARCH "${GH_ARCH}" \
        --arg STATUS "${STATUS_MAP[${STATUS}]}" \
        --arg POOL_ID "${GARM_POOL_ID}" \
        --arg FAULT "${FAULT_VAL}" \
        '{"provider_id": $PROVIDER_ID, "name": $NAME, "os_type": $OS_TYPE, "os_name": $OS_NAME, "os_version": $OS_VERSION, "os_arch": $ARCH, "status": $STATUS, "pool_id": $POOL_ID, "provider_fault": $FAULT}'
}

function DeleteInstance() {
    local instance_id="${GARM_INSTANCE_ID}"
    if [ -z "${instance_id}" ];then
        echo "missing instance ID in env"
        return 1
    fi

    set +e
    instance_info=$(openstack server show "${instance_id}" -f json 2>&1)
    if [ $? -ne 0 ];then
        CODE=$?
        set -e
        if [ "${instance_info}" == "No server with a name or ID of*" ];then
            return 0
        fi
        return $CODE
    fi
    set -e
    VOLUMES=$(echo "${instance_info}" | jq -r -c '.volumes_attached[] | .id')

    openstack server delete "${instance_id}"
    for vol in "$VOLUMES";do
        waitForVolume "${vol}"
        openstack volume delete $vol || true
    done
}

function StartInstance() {
    local instance_id="${GARM_INSTANCE_ID}"
    if [ -z "${instance_id}" ];then
        echo "missing instance ID in env"
        return 1
    fi

    openstack server start "${instance_id}"
}

function StopServer() {
    local instance_id="${GARM_INSTANCE_ID}"
    if [ -z "${instance_id}" ];then
        echo "missing instance ID in env"
        return 1
    fi

    openstack server stop "${instance_id}"
}

function ListInstances() {
    INSTANCES=$(openstack server list --os-compute-api-version 2.52 --tags garm-pool-id=${GARM_POOL_ID} --long -f json)
    echo ${INSTANCES} | jq -r '[
        .[] | .Properties * {
            provider_id: .ID,
            name: .Name,
            status: {"ACTIVE": "running", "SHUTOFF": "stopped", "BUILD": "pending_create", "ERROR": "error", "DELETING": "pending_delete"}[.Status]
        }]'
}

function GetInstance() {
    INSTANCE=$(openstack server show --os-compute-api-version 2.52 ${GARM_INSTANCE_ID} -f json)
    echo ${INSTANCES} | jq -r '.properties * {
        provider_id: .id,
        name: .name,
        status: {"ACTIVE": "running", "SHUTOFF": "stopped", "BUILD": "pending_create", "ERROR": "error", "DELETING": "pending_delete"}[.status]
    }'
}

case "$GARM_COMMAND" in
    "CreateInstance")
        CreateInstance
        ;;
    "DeleteInstance")
        DeleteInstance
        ;;
    "GetInstance")
        GetInstance
        ;;
    "ListInstances")
        ListInstances
        ;;
    "StartInstance")
        StartInstance
        ;;
    "StopInstance")
        StopServer
        ;;
    "RemoveAllInstances")
        echo "RemoveAllInstances not implemented"
        exit 1
        ;;
    *)
        echo "Invalid GARM provider command: \"$GARM_COMMAND\""
        exit 1
        ;;
esac
