#!/bin/bash

# Copyright 2017 Hewlett Packard Enterprise Development LP Licensed under the 
# Apache License, Version 2.0 (the "License"); you may not use this file except 
# in compliance with the License. You may obtain a copy of the License at 
# http://www.apache.org/licenses/LICENSE-2.0 Unless required by applicable law 
# or agreed to in writing, software distributed under the License is distributed 
# on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either 
# express or implied. See the License for the specific language governing 
# permissions and limitations under the License.

function initialize() {
   skip_team=0
}

function validate_macs() {
    if [ `ip link | grep -i "$1" | wc -l` -ne 1 ]; then
        echo "ERROR : MAC address $1 not found, skipping this team"
        skip_team=1
    fi
}

function create_team() {
    # Get interface names
    int_name1=$(echo `ip link | grep -i -B 1 "${mac1}" | head -1 | cut -d':' -f2`)
    int_name2=$(echo `ip link | grep -i -B 1 "${mac2}" | head -1 | cut -d':' -f2`)

    # Define configuration files
    conf_path="/etc/sysconfig/network"
    conf_int1="${conf_path}/ifcfg-${int_name1}"
    conf_int2="${conf_path}/ifcfg-${int_name2}"
    conf_int1_bak="/tmp/ifcfg-${int_name1}.bak"
    conf_int2_bak="/tmp/ifcfg-${int_name2}.bak"

    # Define configuration file for NIC team
    cfg_team="${conf_path}/ifcfg-${team_name}"

    # Find out how these interfaces boot (none, static, dhcp) and if they have an ip
    if [ -f "${conf_int1}" ]; then
        bootproto1=$(grep -i BOOTPROTO "${conf_int1}" | cut -d'=' -f2 | tr '[:upper:]' '[:lower:]')
        ip1=$(echo `ip a | grep -i -A 2 ${int_name1} | grep "inet " | awk -F' ' '{ print $2 }'`)
        team_ip=${ip1}
        #main_int=${int_name1}   # to be used in the team config file as DEVICE 0 
        #second_int=${int_name2} # to be used in the team config file as DEVICE 1
    elif [ -f "${conf_int2}" ]; then
        bootproto2=$(grep -i BOOTPROTO "${conf_int2}" | cut -d'=' -f2 | tr '[:upper:]' '[:lower:]')
        ip2=$(echo `ip a | grep -i -A 2 ${int_name2} | grep "inet " | awk -F' ' '{ print $2 }'`)
        team_ip=${ip2}
        #main_int=${int_name2}   # to be used in the team config file as DEVICE 0
        #second_int=${int_name1} # to be used in the team config file as DEVICE 1
    #else
        #main_int=${int_name1}   # to be used in the team config file as DEVICE 0
        #second_int=${int_name2} # to be used in the team config file as DEVICE 1
    fi

    # create the team network file. Default is DHCP but if a static IP is found, use static
    if [[ ! -z "${ip1}" && "${bootproto1}" == "static" ]]; then
        team_bootproto="static"
        team_ip=${ip1}
    elif [[ ! -z "${ip2}" && "${bootproto2}" == "static" ]]; then
        team_bootproto="static"
        team_ip=${ip2}
    else
        team_bootproto="dhcp"
    fi

    # Stop slave interfaces
    wicked ifdown ${int_name1}
    wicked ifdown ${int_name2}

    # If configuration files exist for the slave interfaces, then remove them (or move to /tmp/<filename>.bak)
    [ -f "${conf_int1}" ] && mv "${conf_int1}" "${conf_int1_bak}"
    [ -f "${conf_int2}" ] && mv "${conf_int2}" "${conf_int2_bak}"

cat > ${cfg_team} << EOF
STARTMODE=auto
BOOTPROTO=${team_bootproto}
TEAM_RUNNER="roundrobin"
TEAM_PORT_DEVICE_0=${int_name1}
TEAM_PORT_DEVICE_1=${int_name2}
TEAM_LW_NAME="ethtool"
TEAM_LW_ETHTOOL_DELAY_UP="10"
TEAM_LW_ETHTOOL_DELAY_DOWN="10"
EOF

if [ ! -z ${team_ip} ]; then
cat >> ${cfg_team} << EOF
IPADDRESS=${team_ip}
EOF
fi


# Details of Wicked configuration file
#wicked show-config ## commented out -> too much unneeded output at this stage

# Start Network Teaming device
wicked ifup all ${team_name}

# Restart the network to start up cleanly
service network restart

# Check the status of Network Teaming device
wicked ifstatus --verbose ${team_name}
teamdctl ${team_name} state
}

## Main

# Check if the nic_teaming variable is empty
nic_teaming="@nic_teaming@"
[ ${#nic_teaming} -eq 0 ] && exit 0

# Read the interfaces into an array
readarray ifaces_list < <(echo "${nic_teaming}")

# Install teamd packages
zypper --non-interactive --no-gpg-checks install libteam-tools libteamdctl0 libteamdctl0 python-libteam

# Go throgh the list of teams to be created
for t in "${ifaces_list[@]}"; do
    initialize
    team_name=$(echo ${t} | cut -d',' -f1)
    mac1=$(echo ${t} | cut -d',' -f2)
    mac2=$(echo ${t} | cut -d',' -f3)
    validate_macs ${mac1} ${mac2}
    [ ${skip_team} -eq 0 ] && create_team
done

exit 0