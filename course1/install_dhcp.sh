#!/usr/bin/env bash

##################################
# Run command: curl https://raw.githubusercontent.com/tinybrick/cloud_course_material/master/course1/install_dhcp.sh | bash /dev/stdin <interface>
#

if [[ -z $1 ]]; then
    echo "$0 <interface>"
    exit 1
fi

yum install -y dhcp

echo Configure DHCP...
yes | cp /usr/lib/systemd/system/dhcpd.service /etc/systemd/system/
sed -i "s/\-\-no\-pid/$1/g" /etc/systemd/system/dhcpd.service

echo Setup IP information...

SUBNET=172.16.0.0
NET_MASK=255.255.255.0
BROADCAST_ADDRESS=172.16.0.255
DHCP_RANGE_FROM=172.16.0.150
DHCP_RANGE_TO=172.16.0.250
DHCP_DOMAIN_NAME_SERVERS=8.8.8.8
DOMAIN_NAME=cloud.local.

DHCP_IP_SELF=172.16.0.1
DHCP_OPTION_ROUTES=$DHCP_IP_SELF

MAC_ADDRESS=`ip link show $1 | awk '/link\/ether/{print $2}'`
REV_SUBNET=$(echo $SUBNET | awk -F. '{for (i=NF-1; i>0; --i) printf "%s%s", $i, (i<NF-2 ? "" : ".")}')

echo "
default-lease-time 600;
max-lease-time 7200;
subnet $SUBNET netmask $NET_MASK {
    range $DHCP_RANGE_FROM $DHCP_RANGE_TO;
    option routers $DHCP_OPTION_ROUTES;
    option domain-name-servers $DHCP_DOMAIN_NAME_SERVERS;
    option domain-name \"$DOMAIN_NAME\";
    option broadcast-address $BROADCAST_ADDRESS;
    host self {
        hardware ethernet $MAC_ADDRESS;
        fixed-address $DHCP_IP_SELF;
    }
}" > /etc/dhcp/dhcpd.conf

dhcpd -t -cf /etc/dhcp/dhcpd.conf
if [ ! 0 = $? ]; then
    echo "Configuration file incorrect, installation abort"
    exit 1
fi

systemctl enable dhcpd
systemctl start dhcpd

iptables -A INPUT -p udp -m udp --sport 67 -j ACCEPT
iptables -A INPUT -p udp -m udp --sport 68 -j ACCEPT
