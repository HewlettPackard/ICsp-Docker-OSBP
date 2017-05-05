#!/bin/bash

# Copyright 2017 Hewlett Packard Enterprise Development LP Licensed under the 
# Apache License, Version 2.0 (the "License"); you may not use this file except 
# in compliance with the License. You may obtain a copy of the License at 
# http://www.apache.org/licenses/LICENSE-2.0 Unless required by applicable law 
# or agreed to in writing, software distributed under the License is distributed 
# on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either 
# express or implied. See the License for the specific language governing 
# permissions and limitations under the License.

## Logging functions

# 0 - no output, 1 - error|warn messages, 2 - info|error|warn messages, 3 - debug|info|error|warn messages
LOG_FILE_LEVEL=${LOG_FILE_LEVEL:-3}
LOG_STDIO_LEVEL=${LOG_STDIO_LEVEL:-2}
LOG_FILE_DRIVER=${LOG_FILE_DRIVER:-1}
LOG_STDIO_DRIVER=${LOG_STDIO_DRIVER:-1}

SCRIPT_LOG=$HOME/bootstrap.log
touch $SCRIPT_LOG

function EMIT_FILE_DRIVER() {
    if [ 1 -eq $LOG_FILE_DRIVER ]; then
        echo -e $2 >> $SCRIPT_LOG
    fi
}

function EMIT_STDIO_DRIVER() {
    if [ 1 -eq $LOG_STDIO_DRIVER ]; then
        echo -e $2
    fi
}

function EMIT_LOG(){
    # 0 - no output, 1 - error|warn messages, 2 - info|error|warn messages, 3 - debug|info|error|warn messages
    case $1 in
        ERROR|WARN) [ $LOG_STDIO_LEVEL -gt 0 ] && EMIT_STDIO_DRIVER "$@" ;;
        INFO)  [ $LOG_STDIO_LEVEL -gt 1 ] && EMIT_STDIO_DRIVER "$@" ;;
        DEBUG) [ $LOG_STDIO_LEVEL -gt 2 ] && EMIT_STDIO_DRIVER "$@" ;;
    esac
    case $1 in
        ERROR|WARN) [ $LOG_FILE_LEVEL -gt 0 ] && EMIT_FILE_DRIVER "$@" ;;
        INFO)  [ $LOG_FILE_LEVEL -gt 1 ] && EMIT_FILE_DRIVER "$@" ;;
        DEBUG) [ $LOG_FILE_LEVEL -gt 2 ] && EMIT_FILE_DRIVER "$@" ;;
    esac
    r=$? #mute the error level for loglevel checks
}

function SCRIPTENTRY(){
    local ln="${BASH_LINENO[0]}"
    timeAndDate=`date`
    script_name=`basename "$0"`
    script_name="${script_name%.*}"
    EMIT_LOG DEBUG "[$timeAndDate] [DEBUG] [$ln] > $script_name $FUNCNAME"
}

function SCRIPTEXIT(){
    local ln="${BASH_LINENO[0]}"
    script_name=`basename "$0"`
    script_name="${script_name%.*}"
    EMIT_LOG DEBUG "[$timeAndDate] [DEBUG] [$ln] < $script_name $FUNCNAME"
}

function ENTRY(){
    local cfn="${FUNCNAME[1]}"
    local ln="${BASH_LINENO[0]}"
    timeAndDate=`date`
    EMIT_LOG DEBUG "[$timeAndDate] [DEBUG] [$ln] > $cfn $FUNCNAME"
}

function EXIT(){
    local cfn="${FUNCNAME[1]}"
    local ln="${BASH_LINENO[0]}"
    timeAndDate=`date`
    EMIT_LOG DEBUG "[$timeAndDate] [DEBUG] [$ln] < $cfn $FUNCNAME"
}

function INFO(){
    local function_name="${FUNCNAME[1]}"
    local msg="$1"
    local ln="${BASH_LINENO[0]}"
    timeAndDate=`date`
    EMIT_LOG INFO "[$timeAndDate] [INFO] [$ln] $msg"
}

function DEBUG(){
    local function_name="${FUNCNAME[1]}"
    local msg="$1"
    local ln="${BASH_LINENO[0]}"
    timeAndDate=`date`
    EMIT_LOG DEBUG "[$timeAndDate] [DEBUG] [$ln] $msg"
}

function ERROR(){
    local function_name="${FUNCNAME[1]}"
    local msg="$1"
    local ln="${BASH_LINENO[0]}"
    timeAndDate=`date`
    EMIT_LOG ERROR "[$timeAndDate] [ERROR] [$ln] $msg"
}

function WARN(){
    local function_name="${FUNCNAME[1]}"
    local msg="$1"
    local ln="${BASH_LINENO[0]}"
    timeAndDate=`date`
    EMIT_LOG WARN "[$timeAndDate] [WARN] [$ln] $msg"
}

#
#
## Variables
docker_service_dir='/etc/systemd/system/docker.service.d'
docker_proxy_conf='http-proxy.conf'
docker_user=docker
docker_repo="@docker_repo@"
RHEL_version_string=7 # only supported version
internal_rhel_repo="@internal_rhel_repo@"
docker_version="@docker_version@"
swarm_leader="@swarm_leader@"
swarm_node="@swarm_node@"

#
#
## Proxy settings
export proxy_hostname=@proxy_hostname@
export proxy_port=@proxy_port@
export http_proxy=http://@proxy_hostname@:@proxy_port@
export https_proxy=https://@proxy_hostname@:@proxy_port@
export no_proxy=@no_proxy@

#
#
## Script functions
function rhn_registration() {
    export TMPPYTHONPATH=$PYTHONPATH
    unset PYTHONPATH # RHN subscription-manager won't work with this one set up from ICsp
    subscription-manager config --server.proxy_hostname=${proxy_hostname} \
                                    --server.proxy_port=${proxy_port}
    subscription-manager register --auto-attach --username=@rhn_user@ --password=@rhn_pw@
    if [ $? -ne 0 ]; then
        # Double checking the RHN registration just in case
        if [ $(subscription-manager status | grep Current | wc -l) -ne 1 ] || [ $(subscription-manager list | grep Subscribed | wc -l) -ne 1 ]; then 
            ERROR 'There was a problem registering this system with the Red Hat Network!'
            exit 1
        fi
    fi
    export PYTHONPATH=$TMPYTHONPATH
}

function install_docker() {
    INFO "Storing Docker EE yum variables"
    echo "${docker_repo}" > /etc/yum/vars/dockerurl
    echo "${RHEL_version_string}" > /etc/yum/vars/dockerosversion

    INFO 'Cleaning up yum cached data...'
    yum -y -q -e 0 clean all 
    [ $? -ne 0 ] && ERROR 'There was a problem running yum clean all!' && exit 1
    
    INFO 'Installing yum utils and setting up the stable repo...'
    yum  -y -q -e 0 install yum-utils deltarpm && \
    yum-config-manager -y -q -e 0 --add-repo ${docker_repo}/docker-ee.repo
    [ $? -ne 0 ] && ERROR 'There was a problem setting the Docker repository!' && exit 1

    INFO 'Installing Docker...'
    yum -y -q -e 0 makecache fast && \
    yum -y -q -e 0 install "docker-ee-${docker_version}*"
    [ $? -ne 0 ] && ERROR 'There was a problem installing Docker EE!' && exit 1

    ## Adding the proxy configuration to the docker daemon env vars
    if [ ! -z "${http_proxy}" ] || [ ! -z "${https_proxy}" ]; then
        INFO 'Adding proxy settings to daemon configuration...'
        env="Environment="
        [ ! -z "${http_proxy}" ]  && env="${env}\"HTTP_PROXY=${http_proxy}\" "
        [ ! -z "${https_proxy}" ] && env="${env}\"HTTPS_PROXY=${https_proxy}\" "
        [ ! -z "${no_proxy}" ]    && env="${env}\"NO_PROXY=${no_proxy}\""
        mkdir ${docker_service_dir}
        echo -e "[Service]\n${env}" > ${docker_service_dir}/${docker_proxy_conf}
    fi
}

function config_storage() {
# This function assumes that the VG has already been created via the kickstart file

INFO 'Creating PV and LVs...'
# Create volume group and logical volumes
lvcreate --wipesignatures y -n lv_thinpool vg_docker -l 95%VG
lvcreate --wipesignatures y -n lv_thinpoolmeta vg_docker -l 1%VG
lvconvert -y --zero n -c 512K --thinpool vg_docker/lv_thinpool --poolmetadata vg_docker/lv_thinpoolmeta

# Configure autoextend settings
INFO 'Configuring autoextend settings...'
cat > '/etc/lvm/profile/docker-thinpool.profile' << EOF
activation {
thin_pool_autoextend_threshold=80
thin_pool_autoextend_percent=20
}
EOF

# Apply lvm profile
INFO 'Applying LVM profile...'
lvchange --metadataprofile docker-thinpool vg_docker/lv_thinpool
# Verify lv is monitored
if [ $(lvs -o+seg_monitor | grep 'monitored' | wc -l) -eq 1 ]; then
    INFO 'Monitoring is set up OK...'
else 
    ERROR 'There was an error setting the monitoring...'
    exit 1
fi

# Configure Docker daemon
INFO 'Configuring the Docker daemon'
mkdir /etc/docker/
cat > '/etc/docker/daemon.json' << EOF
{
  "storage-driver": "devicemapper",
   "storage-opts": [
     "dm.thinpooldev=/dev/mapper/vg_docker-lv_thinpool",
     "dm.use_deferred_removal=true",
     "dm.use_deferred_deletion=true"
   ]
}
EOF
}

function enable_and_start() {
    INFO 'Enabling and starting service...'
    systemctl daemon-reload && \
    systemctl enable docker.service && \
    systemctl start docker.service
    [ $? -ne 0 ] && ERROR 'There was a problem enabling or starting the docker service!' && exit 1
    # Display Docker info
    INFO 'Checking Docker info...'
    docker info
    [ $(docker info | grep 'Storage Driver: devicemapper' | wc -l) -eq 1 ] && [ $(docker info | grep 'Pool Name: vg_docker-lv_thinpool' | wc -l) -eq 1 ] && INFO 'Docker info appears to be as expected. Storage configured correctly!'
    su - docker -c 'docker run hello-world'
}

function configure_internal_RHEL_repo() {
# Disable RedHat managed repo
subscription-manager config --rhsm.manage_repos=0
# Add internal repo
repo="/etc/yum.repos.d/internal.repo"
cat > ${repo} << EOF
[Internal_RHEL_repo]
name=Internal_RHEL_repo
gpgcheck=0
enabled=1
baseurl=${internal_rhel_repo}
EOF
}

function config_swarm() {
    if [ ${#swarm_leader} -gt 0 ]; then 
        docker swarm init --advertise-addr ${swarm_leader}
        [ $? -ne 0 ] && ERROR 'There was a problem initializing the swarm. Is the IP provided correct and reachable?' && exit 1
        # Generate command to join swarm as a worker
        docker swarm join-token worker
        # Generate command to join swarm as a manager
        docker swarm join-token manager
    elif [ ${#swarm_node} -gt 0 ]; then
        eval "${swarm_node}"
        [ $? -ne 0 ] && ERROR 'There was a problem joining the swarm. Please check the error log for additional information.' && exit 1
    fi
}

function additional_config() {
    ## Allow root logins using SSH
    # Replace any entry of "PermitRootLogin..." or "#PermitRootLogin..." with "PermitRootLogin no"
    sed -i  's/^[\#]\?PermitRootLogin.*/PermitRootLogin no/g' /etc/ssh/sshd_config 
    # If nothing was found in the step above then just add the line to the sshd config file
    [ $(grep "PermitRootLogin no" /etc/ssh/sshd_config | wc -l) -eq 0 ] && echo "PermitRootLogin no" >> /etc/ssh/sshd_config
    # Restart the service
    service sshd restart
}

#
#
## Main
# If using an internal repo we assume the internet access is restricted and don't register the system with RHN
if [ ${#internal_rhel_repo} -gt 0 ]; then
    configure_internal_RHEL_repo
else
    rhn_registration
fi
install_docker
config_storage
enable_and_start
config_swarm
additional_config
exit 0