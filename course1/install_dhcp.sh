#!/usr/bin/env bash
##################################
# Run command:
#  $ sudo curl https://raw.githubusercontent.com/tinybrick/cloud_course_material/master/course1/install_dhcp.sh | bash /dev/stdin <interface>
#

if [[ -z $4 ]]; then
    echo "$0 [interface] [from_ip] [to_ip] [domain_name]"
    exit 1
fi

ip2int()
{
    local a b c d
    { IFS=. read a b c d; } <<< $1
    echo $(((((((a << 8) | b) << 8) | c) << 8) | d))
}

int2ip()
{
    local ui32=$1; shift
    local ip n
    for n in 1 2 3 4; do
        ip=$((ui32 & 0xff))${ip:+.}$ip
        ui32=$((ui32 >> 8))
    done
    echo $ip
}

netmask()
{
    local mask=$((0xffffffff << (32 - $1)))
    int2ip $mask
}


broadcast()
{
    local addr=$(ip2int $1)
    local mask=$((0xffffffff << (32 - $2)))
    int2ip $((addr | ~mask))
}

get_subnet()
{
    local addr=$(ip2int $1)
    local mask=$((0xffffffff << (32 -$2)))
    int2ip $((addr & mask))
}


DHCP_CONFIG_FILE=/etc/dhcp/dhcpd.conf

yum install -y dhcp
if [ ! 0 = $? ]; then
    echo "DHCP package install failed, installation aborted"
    exit 2
fi

echo Configure DHCP...
yes | cp /usr/lib/systemd/system/dhcpd.service /etc/systemd/system/
sed -i "s/\-\-no\-pid/$1/g" /etc/systemd/system/dhcpd.service

echo Setup IP information...
INTERFACE=$1
DHCP_RANGE_FROM=$2
DHCP_RANGE_TO=$3
DOMAIN_NAME=$4.
DHCP_DOMAIN_NAME_SERVERS="8.8.8.8"

DHCP_IP_SELF=`ip addr show dev $INTERFACE | awk '/inet\ /{print $2}' | awk -F/ '{print $1}'`
NET_MASK_SHORT_FORMAT=`ip addr show dev $INTERFACE | awk '/inet\ /{print $2}' | awk -F/ '{print $2}'`
NET_MASK=$(netmask $NET_MASK_SHORT_FORMAT)
SUBNET=$(get_subnet $DHCP_IP_SELF $NET_MASK_SHORT_FORMAT)
MAC_ADDRESS=`ip link show $INTERFACE | awk '/link\/ether/{print $2}'`
DHCP_OPTION_ROUTES=`ip route get $SUBNET/$NET_MASK_SHORT_FORMAT | awk '/'$INTERFACE'\ /{print $6}'`
BROADCAST_ADDRESS=`ip addr show dev $INTERFACE | awk '/inet\ /{print $4}' | awk -F/ '{print $1}'`
REV_SUBNET=$(echo $SUBNET | awk -F. '{for (i=NF-1; i>0; --i) printf "%s%s", $i, (i<NF-2 ? "" : ".")}')

if [ -f $DHCP_CONFIG_FILE ]; then
    yes | cp $DHCP_CONFIG_FILE $DHCP_CONFIG_FILE.bak
fi

echo "default-lease-time 600;
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
    if [ -f $DHCP_CONFIG_FILE.bak ]; then
        yes | cp $DHCP_CONFIG_FILE.bak $DHCP_CONFIG_FILE
    else
        rm -f /etc/dhcp/dhcpd.conf
    fi

    echo "Configuration file incorrect, installation aborted"
    exit 3
fi

systemctl enable dhcpd
systemctl start dhcpd

iptables -A INPUT -p udp -m udp --sport 67 -j ACCEPT
iptables -A INPUT -p udp -m udp --sport 68 -j ACCEPT

echo "DHCP server install success"
