#!/bin/bash

# Copyright 2017 Hewlett Packard Enterprise Development LP Licensed under the 
# Apache License, Version 2.0 (the "License"); you may not use this file except 
# in compliance with the License. You may obtain a copy of the License at 
# http://www.apache.org/licenses/LICENSE-2.0 Unless required by applicable law 
# or agreed to in writing, software distributed under the License is distributed 
# on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either 
# express or implied. See the License for the specific language governing 
# permissions and limitations under the License.

#
## Functions

function create_team() {
    echo "Creating team: ${team_name}"
    # Get interface names
    int_name1=$(echo `ip link | grep -i -B 1 "${mac1}" | head -1 | cut -d':' -f2`)
    int_name2=$(echo `ip link | grep -i -B 1 "${mac2}" | head -1 | cut -d':' -f2`)
    # Get configuration files
    cfg_int1="/etc/sysconfig/network-scripts/ifcfg-${int_name1}"
    cfg_int2="/etc/sysconfig/network-scripts/ifcfg-${int_name2}"
    cfg_team="/etc/sysconfig/network-scripts/ifcfg-team-${team_name}"
    # Find out how these interfaces boot (none, static, dhcp)
    bootproto1=$(grep -i BOOTPROTO "${cfg_int1}" | cut -d'=' -f2 | tr '[:upper:]' '[:lower:]')
    bootproto2=$(grep -i BOOTPROTO "${cfg_int2}" | cut -d'=' -f2 | tr '[:upper:]' '[:lower:]')
    # Check if they have an IP address configured
    ip1=$(echo `ip a | grep -i -A 2 ${int_name1} | grep "inet " | awk -F' ' '{ print $2 }' | cut -d'/' -f1`)
    ip2=$(echo `ip a | grep -i -A 2 ${int_name2} | grep "inet "| awk -F' ' '{ print $2 }' | cut -d'/' -f1`)
    # Create team using nmcli
    nmcli connection add type team ifname ${team_name}
    nmcli con add type team-slave con-name ${team_name}-port1 ifname ${int_name1} master ${team_name}
    nmcli con add type team-slave con-name ${team_name}-port2 ifname ${int_name2} master ${team_name}
    # Default is DHCP but if we find a static IP we'll use this one instead
    if [[ ! -z "${ip1}" && "${bootproto1}" == "static" ]]; then
        echo "Using static IP $ip1 for the team NIC."
        grep -Ei '^DNS|^IPADDR|^NETMASK|^GATEWAY|^BOOTPROTO' ${cfg_int1} >> ${cfg_team}
        sed -i '/BOOTPROTO=dhcp/d' ${cfg_team}
    elif [[ ! -z "${ip2}" && "${bootproto2}" == "static" ]]; then
        echo "Using static IP $ip2 for the team NIC."
        grep -Ei '^DNS|^IPADDR|^NETMASK|^GATEWAY|^BOOTPROTO' ${cfg_int2} >> ${cfg_team}
        sed -i '/BOOTPROTO=dhcp/d' ${cfg_team}
    else
        echo "Using DHCP for the team NIC."
    fi
    # Activate the team and restart the network 
    nmcli connection up ${team_name}-port1
    nmcli connection up ${team_name}-port2
    nmcli connection up team-${team_name}
    nmcli connection show
    systemctl restart network
}

function validate_macs() {
    if [ `ip link | grep -i "$1" | wc -l` -ne 1 ]; then
        echo "ERROR : MAC address $1 not found, skipping this team"
        skip_team=1
    fi
}

function initialize() {
    skip_team=0
}

#
## Main

# Check if the nic_teaming variable is empty
nic_teaming="@nic_teaming@"
[ ${#nic_teaming} -eq 0 ] && exit 0

# Read the interfaces into an array
readarray ifaces_list < <(echo "${nic_teaming}")

# Install teamd package in case it's missing
yum -y install teamd

# Go through the list of teams to be created
for t in "${ifaces_list[@]}"; do
    initialize
    team_name=$(echo ${t} | cut -d',' -f1)
    mac1=$(echo ${t} | cut -d',' -f2)
    mac2=$(echo ${t} | cut -d',' -f3)
    validate_macs ${mac1} ${mac2}
    [ ${skip_team} -eq 0 ] && create_team
done

exit 0
