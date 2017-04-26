# Copyright 2017 Hewlett Packard Enterprise Development LP Licensed under the 
# Apache License, Version 2.0 (the "License"); you may not use this file except 
# in compliance with the License. You may obtain a copy of the License at 
# http://www.apache.org/licenses/LICENSE-2.0 Unless required by applicable law 
# or agreed to in writing, software distributed under the License is distributed 
# on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either 
# express or implied. See the License for the specific language governing 
# permissions and limitations under the License.
lang en_US.UTF-8
keyboard us
timezone --utc America/Chicago
text 
install
skipx
network  --bootproto=dhcp

authconfig --enableshadow --enablemd5
rootpw --iscrypted "@encrypted_root_password:$1$7z4m7f1z$wliShMhVv2HuCAPmuiQzV1@"
user --groups=wheel --homedir=/home/docker --name=docker --password="@encrypted_root_password:$1$7z4m7f1z$wliShMhVv2HuCAPmuiQzV1@" --iscrypted --gecos="docker"

zerombr
clearpart --all --initlabel
part /boot --fstype xfs --size=300
part /boot/efi --fstype efi --size=300
part swap --size=1024
part pv.01 --size=15000 --grow
part pv.02 --size=10000 --grow
volgroup vg_root pv.01
logvol  /  --vgname=vg_root --size=10000 --name=lv_root
volgroup vg_docker pv.02

bootloader --append="@kernel_arguments: @" --location=mbr

# Disable firewall and selinux for SPP components
firewall --disabled
# Port 1002 is needed for agent communication if the firewall is enabled
# firewall --enable --port=1002:tcp
selinux --disabled

%pre
# Set FCOEwait Custom Attribute to 120 seconds when deploying to FCOE SAN through 
# Broadcom CNA to allow FCOE driver to load correctly
sleep @FCOEwait:0@
%end

%packages
@Base
# Needed to ensure Mellanox driver installed when required
#kmod-mlnx-ofa_kernel

# Components listed below are needed for mount to media server for HPSUM installation
keyutils
libtalloc
cifs-utils

# Components listed below are needed to run HPSUM and SPP components
expat.i686
expect
fontconfig.i686
freetype.i686
libICE.i686
libSM.i686
libuuid.i686
libXi.i686
libX11.i686
libXau.i686
libxcb.i686
libXcursor.i686
libXext.i686
libXfixes.i686
libXi.i686
libXinerama.i686
libXrandr.i686
libXrender.i686
zlib.i686 
libgcc.i686
libstdc++.i686
libhbaapi
make
net-snmp
net-snmp-libs
%end