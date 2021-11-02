#! /bin/bash

DEVSTACK_PATH='/opt/stack/devstack'
LOCAL_INTERFACE=$(ip route get 8.8.8.8 | awk -- '{printf $5}')
SECOND_INTERFACE=${1}
LOCAL_CONF='/opt/stack/devstack/local.conf'
HOST_IP=`/sbin/ifconfig | grep '\<inet\>' | sed -n '1p' | tr -s ' ' | cut -d ' ' -f3 | cut -d ':' -f2`
OPENSTACK_PATH="/usr/local/bin/openstack"

### Make sure only root can run our script
if (( $EUID != 0 )); then
	echo "This script must be run as root"
	echo $EUID
	exit
fi

### Translate sources
sed -i 's/kr.archive.ubuntu.com/mirror.kakao.com/g' /etc/apt/sources.list
sed -i 's/security.ubuntu.com/mirror.kakao.com/g' /etc/apt/sources.list

### Update and Upgrade
apt update && apt dist-upgrade -y

### Install pip
apt install python3-pip -y
pip install --upgrade pip
pip3 install setuptools==57.4.0


### Make stack user
useradd -s /bin/bash -d /opt/stack -m stack
echo "stack ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/stack

### Install Devstack
if [ -f $DEVSTACK_PATH ]; then
	echo "devstack file exist"
else
	echo "devstack file not exist"
        su - stack -c "git clone https://git.openstack.org/openstack-dev/devstack -b stable/ussuri"
###        su - stack -c rm -rf /opt/stack/devstack/tools/install_pip.sh
fi

while :
do	
	echo -e '\nEnter Your Openstack PASSWD: '
	read -s PASSWD
	echo -e 'Check Your Openstack PASSWD: '
	read -s CHECK_PASSWD

	if [ $PASSWD == $CHECK_PASSWD ]; then
		break
	else
		echo 'PASSWORD is not correct'
	fi
done
echo ''
### Check local.conf File
while :
do
	if [ ! -e $LOCAL_CONF ]; then
		echo "Make local.conf file"
		touch $LOCAL_CONF
		echo -e '[[local|localrc]]\nHOST_IP='${HOST_IP}'\nADMIN_PASSWORD='${PASSWD}\
		'\nMYSQL_PASSWORD=$ADMIN_PASSWORD\nRABBIT_PASSWORD=$ADMIN_PASSWORD\nSERVICE_PASSWORD=$ADMIN_PASSWORD\nSERVICE_TOKEN=$ADMIN_PASSWORD'\
		'\n\nFLAT_INTERFACE='${SECOND_INTERFACE}''\
	       '\nVOLUME_BACKING_FILE_SIZE=200G\nPIP_USE_MIRRORS=False\nUSE_GET_PIP=1'\
	       '\n\nLOGFILE=$DEST/logs/stack.sh.log\nVERBOSE=True\nENABLE_DEBUG_LOG_LEVEL=True\nENABLE_VERBOSE_LOG_LEVEL=True'\
	       '\nQ_PLUGIN=ml2\nQ_AGENT=openvswitch\nQ_USE_SECGROUP=False\nLIBVIRT_FIREWALL_DRIVER=nova.virt.firewall.NoopFirewallDriver'\
	       '\nenable_plugin heat https://opendev.org/openstack/heat stable/ussuri\nenable_plugin networking-sfc https://opendev.org/openstack/networking-sfc stable/ussuri'\
	       '\nenable_plugin barbican https://opendev.org/openstack/barbican stable/ussuri\nenable_plugin mistral https://opendev.org/openstack/mistral stable/ussuri'\
	       '\nCEILOMETER_EVENT_ALARM=True\nenable_plugin ceilometer https://opendev.org/openstack/ceilometer stable/ussuri\nenable_plugin aodh https://opendev.org/openstack/aodh stable/ussuri'\
	       '\nenable_plugin blazar https://github.com/openstack/blazar.git stable/ussuri\nenable_plugin fenix https://opendev.org/x/fenix.git master'\
	       '\nenable_plugin tacker https://github.com/SSU-DCN/tacker feature/prometheus'\
	       '\nenable_service n-novnc\nenable_service n-cauth\ndisable_service tempest'\
	       '\n\n[[post-config|/etc/neutron/dhcp_agent.ini]]\n[DEFAULT]\nenable_isolated_metadata=True\n' >> $LOCAL_CONF
		break
	else
		rm -rf $LOCAL_CONF
		echo 'Delete original local.conf'
	fi
done

### Fix outfilter.py
OUTFILTER_PATH='/opt/stack/devstack/tools/outfilter.py'
sed -i "s/outfile.write(ts_line.encode('utf-8'))/outfile.write(ts_line.encode('utf-8','surrogatepass'))/g" $OUTFILTER_PATH

### Start Install Openstack
su - stack -c "devstack/stack.sh"

### Ovs setting
su - stack -c "sudo ovs-vsctl add-port br-ex ${SECOND_INTERFACE}"

### Start openrc
source ${DEVSTACK_PATH}/openrc admin admin

### Setting SEC_GROUP
SEC_ID="$(${OPENSTACK_PATH} security group list --project admin | grep default | cut -f 2 -d ' ')"

while :
do
	RULE_ID="$(${OPENSTACK_PATH} security group rule list ${SEC_ID} | grep None | sed -n '1p' | cut -f 2 -d ' ')"
	if [ -z "${RULE_ID}"  ]; then
		echo "SEC_GROUP Delete Complete !"
		break
	fi
	${OPENSTACK_PATH} security group rule delete ${RULE_ID}

done

${OPENSTACK_PATH} security group rule create ${SEC_ID} --protocol any --egress
${OPENSTACK_PATH} security group rule create ${SEC_ID} --protocol any --ingress
${OPENSTACK_PATH} security group rule create ${SEC_ID} --protocol tcp --dst-port 22:22

### Setting Public Network
ROUTER_ID="$(${OPENSTACK_PATH} router list | grep ACTIVE | cut -f 2 -d ' ')"
PORT_ID_1="$(${OPENSTACK_PATH} router show router1 | grep "port_id" | cut -f 4 -d '"')"
PORT_ID_2="$(${OPENSTACK_PATH} router show router1 | grep "port_id" | cut -f 16 -d '"')"

${OPENSTACK_PATH} router remove port router1 ${PORT_ID_1}
${OPENSTACK_PATH} router remove port router1 ${PORT_ID_2}
${OPENSTACK_PATH} router delete ${ROUTER_ID}

PUBLIC_ID="$(${OPENSTACK_PATH} network list | grep public | cut -f 2 -d ' ')"
${OPENSTACK_PATH} network delete ${PUBLIC_ID}

${OPENSTACK_PATH} network create --project admin --provider-network-type flat --provider-physical-network public --share --external public

HOST_IP_1=`echo ${HOST_IP} | cut -f 1 -d '.'` 
HOST_IP_2=`echo ${HOST_IP} | cut -f 2 -d '.'` 
HOST_IP_3=`echo ${HOST_IP} | cut -f 3 -d '.'` 

HOST_IP_CIDR=${HOST_IP_1}"."${HOST_IP_2}"."${HOST_IP_3}".0/24"
GATEWAY=${HOST_IP_1}"."${HOST_IP_2}"."${HOST_IP_3}".1"
DNS_SERVER="8.8.8.8"

${OPENSTACK_PATH} subnet create --project admin --network public --subnet-range ${HOST_IP_CIDR} --gateway ${GATEWAY} --dns-nameserver ${DNS_SERVER} --ip-version 4 public_subnet

### Download Ubuntu Image 18.04
FILE_ID="1gWL91lkHUjH8Mm-mIRj-LPDk9joUDtKI"
IMAGE="ubuntu_18.04.img"

curl -sc /tmp/cookie "https://drive.google.com/uc?export=download&id=${FILE_ID}" > /dev/null
code="$(awk '/_warning_/ {print $NF}' /tmp/cookie)"
curl -Lb /tmp/cookie "https://drive.google.com/uc?export=download&confirm=${code}&id=${FILE_ID}" -o ${IMAGE}

${OPENSTACK_PATH} image create --disk-format raw --file /root/ubuntu_18.04.img --shared ubuntu_18.04

echo "********************OPENSTACK INSTALLATION AND BASIC SETTING IS FINISHED !!!!********************"



