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
docker_config_file='/etc/default/docker'
docker_user=docker
docker_repo="@docker_repo@"
docker_version="@docker_version@"
internal_ubuntu_repo="@internal_ubuntu_repo@"
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
function install_docker() {
    INFO 'Updating the system...'
    # Cleans up apt-get output and avoid some harmless errors
    export DEBIAN_FRONTEND=noninteractive
    apt-get -o Dpkg::Options::="--force-confold" -qq -y update

    INFO 'Installing required packages and setting up the repository...'
    apt-get -o Dpkg::Options::="--force-confold" -qq -y install apt-transport-https curl software-properties-common > /dev/null
    [ $? -ne 0 ] && ERROR 'There was a problem installing the required packages!' && exit 1
    curl -fsSL ${docker_repo}/gpg | sudo apt-key add - 
    [ $? -ne 0 ] && ERROR 'There was a problem retrieving the GPG key!' && exit 1
    if [ ${#docker_version} -gt 0 ]; then
        add-apt-repository "deb [arch=amd64] ${docker_repo} $(lsb_release -cs) stable-${docker_version}"
    else
        add-apt-repository "deb [arch=amd64] ${docker_repo} $(lsb_release -cs) stable"
    fi
    [ $? -ne 0 ] && ERROR 'There was a problem setting the Docker repository!' && exit 1

    INFO 'Installing Docker...'
    apt-get -o Dpkg::Options::="--force-confold" -qq -y update && \
    apt-get -o Dpkg::Options::="--force-confold" -qq -y install docker-ee > /dev/null
    [ $? -ne 0 ] && ERROR 'There was a problem installing Docker EE!' && exit 1

    ## Adding the proxy configuration to the docker daemon env vars
    if [ ! -z "${http_proxy}" ] || [ ! -z "${https_proxy}" ]; then
        INFO 'Adding proxy settings to daemon configuration...'
        [ ! -z "${http_proxy}" ]  && echo -e "export http_proxy=${http_proxy}" >> ${docker_config_file}
        [ ! -z "${https_proxy}" ] && echo -e "export https_proxy=${https_proxy}" >> ${docker_config_file}
        [ ! -z "${no_proxy}" ]    && echo -e "export no_proxy=${no_proxy}" >> ${docker_config_file}
    fi
}

function config_storage() {
    docker_conf="/etc/init/docker.conf"
    tmp_conf="/tmp/docker.conf"
    if [ $(grep aufs /proc/filesystems | wc -l) -eq 0 ]; then 
        INFO 'Installing aufs packages...'
        apt-get -o Dpkg::Options::="--force-confold" -qq -y install linux-image-extra-$(uname -r) linux-image-extra-virtual > /dev/null
    fi
    # Configure Docker daemon
    INFO 'Configuring the Docker daemon'
    awk 'NR==1,/DOCKER_OPTS=/{sub(/DOCKER_OPTS=/, "DOCKER_OPTS=\"--storage-driver=aufs\"")} 1' ${docker_conf} > ${tmp_conf}
    cp ${tmp_conf} ${docker_conf}
    [ $(grep 'DOCKER_OPTS="--storage-driver=aufs"' /etc/init/docker.conf | wc -l) -ne 1 ] && ERROR 'There was a problem configuring the aufs storage!' && exit 1

}

function enable_and_start() {
    INFO 'Enabling and restarting service...'
    service docker restart
    [ $? -ne 0 ] && ERROR 'There was a problem enabling or starting the docker service!' && exit 1
    # Display Docker info
    INFO 'Checking Docker info...'
    docker info
    [ $(docker info | grep 'Storage Driver: aufs' | wc -l) -eq 1 ] && INFO 'Docker info appears to be as expected. Storage configured correctly!'
    /usr/sbin/usermod -aG docker docker
    docker run hello-world
}

function configure_internal_ubuntu_repo() {
    INFO "Creating internal repo using provided URL: ${internal_ubuntu_repo}"
    mv /etc/apt/sources.list /etc/apt/sources.list.old
    echo "deb ${internal_ubuntu_repo} trusty main" > /etc/apt/sources.list
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

#
#
## Main
if [ ${#internal_ubuntu_repo} -gt 0 ]; then
    configure_internal_ubuntu_repo
fi
install_docker
config_storage
enable_and_start
config_swarm
exit 0