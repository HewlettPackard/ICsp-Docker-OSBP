#!/bin/bash

# Copyright 2017 Hewlett Packard Enterprise Development LP Licensed under the 
# Apache License, Version 2.0 (the "License"); you may not use this file except 
# in compliance with the License. You may obtain a copy of the License at 
# http://www.apache.org/licenses/LICENSE-2.0 Unless required by applicable law 
# or agreed to in writing, software distributed under the License is distributed 
# on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either 
# express or implied. See the License for the specific language governing 
# permissions and limitations under the License.

function create_bond() {
    INTERFACES="/etc/network/interfaces"
    TEMP_INTERFACES="/tmp/temp_interfaces"

    # Save original
    cp ${INTERFACES} ${INTERFACES}.orig

    # Get interface names
    int_name1=$(echo `ip link | grep -i -B 1 "${mac1}" | head -1 | cut -d':' -f2`)
    int_name2=$(echo `ip link | grep -i -B 1 "${mac2}" | head -1 | cut -d':' -f2`)

    # Find out how these interfaces boot (none, static, dhcp)
    bootproto1=$(grep "$int_name1" ${INTERFACES} | grep inet | cut -d' ' -f4)
    bootproto2=$(grep "$int_name2" ${INTERFACES} | grep inet | cut -d' ' -f4)

    # Collect and check the configured IP addressed
    ip1=$(echo `ip a | grep -i -A 2 ${int_name1} | grep "inet " | awk -F' ' '{ print $2 }' | cut -d'/' -f1`)
    ip2=$(echo `ip a | grep -i -A 2 ${int_name2} | grep "inet " | awk -F' ' '{ print $2 }' | cut -d'/' -f1`)
    [ ${#ip1} -eq 0 ] && [ ${#ip2} -eq 0 ] && echo "No IP was configured in any of the provided NICs. Exiting." && exit 0

    ## Create new interfaces file

    # The following code will start building a new temp interfaces file without the 2 NICs that are going to be bonded
    [ -f ${TEMP_INTERFACES} ] && rm ${TEMP_INTERFACES}
    found=0
    while IFS='' read -r line || [[ -n "${line}" ]]; do
        if [ `echo ${line} | grep -E "(iface ${int_name1}|iface ${int_name2})" | wc -l` -eq 1 ]; then
            found=1
        elif [[ $found -eq 1 && `echo $line | grep iface | wc -l` -eq 0 ]]; then
            found=1
            [ `echo ${line} | grep -i "netmask" | wc -l` -eq 1 ] && netmask=`echo ${line} | cut -d' ' -f2`
            [ `echo ${line} | grep -i "gateway" | wc -l` -eq 1 ] && gateway=`echo ${line} | cut -d' ' -f2`
            [ `echo ${line} | grep -i "gw "     | wc -l` -eq 1 ] && gateway=`echo ${line} | awk -F'gw' '{ print $2 }' | awk '{ print $1}'`
        else
            found=0
            echo "${line}" >> ${TEMP_INTERFACES}
        fi
    done < ${INTERFACES}

    # Adding now the two NICs and the bond information
    echo "" >> ${TEMP_INTERFACES}
    echo "auto ${int_name1}" >> ${TEMP_INTERFACES}
    echo "iface ${int_name1} inet manual" >> ${TEMP_INTERFACES}
    echo "bond-master ${bond_name}" >> ${TEMP_INTERFACES}
    echo "bond-primary ${int_name1}" >> ${TEMP_INTERFACES}
    echo "" >> ${TEMP_INTERFACES}
    echo "auto ${int_name2}" >> ${TEMP_INTERFACES}
    echo "iface ${int_name2} inet manual" >> ${TEMP_INTERFACES}
    echo "bond-master ${bond_name}" >> ${TEMP_INTERFACES}
    echo "" >> ${TEMP_INTERFACES}
    echo "auto ${bond_name}" >> ${TEMP_INTERFACES}
    echo "iface ${bond_name} inet static" >> ${TEMP_INTERFACES}
    if [[ ! -z "${ip1}" ]]; then
        echo "address ${ip1}" >> ${TEMP_INTERFACES}
        echo "netmask ${netmask}" >> ${TEMP_INTERFACES}
        [ ${#gateway} -gt 0 ] && echo "gateway ${gateway}" >> ${TEMP_INTERFACES}
    elif [[ ! -z "${ip2}" ]]; then
        echo "address ${ip2}" >> ${TEMP_INTERFACES}
        echo "netmask ${netmask}" >> ${TEMP_INTERFACES}
        [ ${#gateway} -gt 0 ] && echo "gateway ${gateway}" >> ${TEMP_INTERFACES}
    fi
    echo "bond-mode active-backup" >> ${TEMP_INTERFACES}
    echo "bond-miimon 100" >> ${TEMP_INTERFACES}
    echo "bond-slaves none" >> ${TEMP_INTERFACES}

    # Update the /etc/network/interfaces file
    cp ${TEMP_INTERFACES} ${INTERFACES}
    
    # "Restart" the network
    # The usual service networking restart would not work so we have to be creative here
    # (https://bugs.launchpad.net/ubuntu/+source/ifupdown/+bug/1301015)
    ip addr flush ${int_name1}
    ip addr flush ${int_name2}
    ifdown --exclude=lo -a && ifup --exclude=lo -a
}

function validate_macs() {
    if [ `ip link | grep -i "$1" | wc -l` -ne 1 ]; then
        echo "ERROR : MAC address $1 not found, skipping this bond"
        skip_bond=1
    fi
}

function initialize() {
    skip_bond=0
}

#
## Main

# Cleans up apt-get output and avoid some harmless errors
export DEBIAN_FRONTEND=noninteractive

# Read the interfaces into an array
readarray ifaces_list < <(echo "@nic_bonds@")

# Set the proxy and install ifenslave package
export proxy_hostname=@proxy_hostname@
export proxy_port=@proxy_port@
export http_proxy=http://@proxy_hostname@:@proxy_port@
export https_proxy=https://@proxy_hostname@:@proxy_port@
export no_proxy=@no_proxy@
apt-get -o Dpkg::Options::="--force-confold" -qq -y update && apt-get install -o Dpkg::Options::="--force-confold" -qq -y ifenslave > /dev/null

# Permanently load bonding module
[ $(grep bonding /etc/modules | wc -l) -eq 0 ] && echo "bonding" >> /etc/modules

# Go through the list of bonds to be created
for t in "${ifaces_list[@]}"; do
    initialize
    bond_name=$(echo ${t} | cut -d',' -f1)
    mac1=$(echo ${t} | cut -d',' -f2)
    mac2=$(echo ${t} | cut -d',' -f3)
    validate_macs ${mac1} ${mac2}
    [ ${skip_bond} -eq 0 ] && create_bond
done

exit 0