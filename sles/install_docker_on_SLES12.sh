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
docker_version="@docker_version@"
internal_sles_repo="@internal_sles_repo@"
sles_version="12.3" # Only supported version
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
    INFO 'Removing previous repo (if any)...'
    zypper --non-interactive rr docker-ee-stable >> /dev/null 2>&1

    INFO 'Installing the Docker repository...'
    if [ ${#docker_version} -gt 0 ]; then
        zypper addrepo ${docker_repo}/${sles_version}/x86_64/stable-${docker_version} docker-ee-stable && zypper --no-gpg-checks refresh
    else
        zypper addrepo ${docker_repo}/${sles_version}/x86_64/stable docker-ee-stable && zypper --no-gpg-checks refresh
    fi
    [ $? -ne 0 ] && ERROR 'There was a problem setting the Docker repository!' && exit 1

    # We rebuild the DB to avoid occasional failures when caching the rpm database 
    rpmdb --rebuilddb

    INFO 'Installing Docker...'
    zypper --non-interactive --no-gpg-checks install docker-ee
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

function enable_and_start() {
    INFO 'Enabling and starting service...'
    systemctl daemon-reload && \
    systemctl enable docker.service && \
    systemctl start docker.service
    [ $? -ne 0 ] && ERROR 'There was a problem enabling or starting the docker service!' && exit 1
    # Display Docker info
    INFO 'Checking Docker info...'
    docker info
    [ $(docker info | grep 'Storage Driver: btrfs' | wc -l) -eq 1 ] && INFO 'Docker info appears to be as expected. Default storage Btrfs is correct!'
    # Add docker user to the docker group
    /usr/sbin/usermod -aG docker docker
    su - docker -c 'docker run hello-world'
}

function configure_internal_sles_repo() {
    # Disable SLES default repos first 
    SLES_repos=$(zypper repos | grep "SLES12" | grep -v '#' | cut -f1 -d' ')
    for repo in ${SLES_repos}; do 
        zypper modifyrepo -dr ${repo}
    done
    # Add internal repo
    zypper addrepo ${internal_sles_repo} Internal_repo
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
if [ ${#internal_sles_repo} -gt 0 ]; then
    configure_internal_sles_repo
fi
install_docker
enable_and_start
config_swarm
additional_config
exit 0