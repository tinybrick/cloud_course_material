#!/usr/bin/env bash

##################################
# Run command:
#  $ sudo curl https://raw.githubusercontent.com/tinybrick/cloud_course_material/master/course1/install_dhcp.sh | bash /dev/stdin <interface>
#

if [[ -z $4 ]]; then
    echo "$0 [interface] [from_ip] [to_ip] [domain_name]"
    exit 1
fi

INET_NTOA() {
    local IFS=. num quad ip e
    num=$1
    for e in 3 2 1
    do
        (( quad = 256 ** e))
        (( ip[3-e] = num / quad ))
        (( num = num % quad ))
    done
    ip[3]=$num
    echo "${ip[*]}"
}

INET_ATON ()
{
    local IFS=. ip num e
    ip=($1)
    for e in 3 2 1
    do
        (( num += ip[3-e] * 256 ** e ))
    done
    (( num += ip[3] ))
    echo "$num"
}

GET_SUBNET() {
    if [ -z $2 ]; then
       echo Usage: $0 [ip] [netmask]
       exit 1
    fi

    IP="$1"
    NM="$2"

    #
    n="${NM%.*}";m="${NM##*.}"
    l="${IP%.*}";r="${IP##*.}";c=""
    if [ "$m" = "0" ]; then
       c=".0"
       m="${n##*.}";n="${n%.*}"
       r="${l##*.}";l="${l%.*}"
       if [ "$m" = "0" ]; then
          c=".0$c"
          m="${n##*.}";n="${n%.*}"
          r="${l##*.}";l="${l%.*}"
          if [ "$m" = "0" ]; then
             c=".0$c"
             m=$n
             r=$l;l=""
          fi
       fi
    fi
    let s=256-$m
    let r=$r/$s*$s
    if [ "$l" ]; then
       SNW="$l.$r$c"
    else
       SNW="$r$c"
    fi
    #
    echo $SNW
}

yum install -y dhcp
if [ ! 0 = $? ]; then
    echo "DHCP package install failed, installation aborted"
    exit 2
fi

echo Configure DHCP...
yes | cp /usr/lib/systemd/system/dhcpd.service /etc/systemd/system/
sed -i "s/\-\-no\-pid/$1/g" /etc/systemd/system/dhcpd.service

echo Setup IP information...
DHCP_IP_SELF=`ip addr show dev $1 | awk '/inet\ /{print $2}' | awk -F/ '{print $1}'`
BROADCAST_ADDRESS=`ip addr show dev $1 | awk '/inet\ /{print $4}' | awk -F/ '{print $1}'`
NET_MASK="$(INET_NTOA "$((4294967296-(1 << (32 - `ip addr show dev enp0s8 | awk '/inet\ /{print $2}' | awk -F/ '{print $2}'`))))")"
SUBNET="$(GET_SUBNET $DHCP_IP_SELF $NET_MASK)"
MAC_ADDRESS=`ip link show $1 | awk '/link\/ether/{print $2}'`

DHCP_RANGE_FROM=$2
DHCP_RANGE_TO=$3
DOMAIN_NAME=$4.
DHCP_DOMAIN_NAME_SERVERS=8.8.8.8
DHCP_OPTION_ROUTES=$DHCP_IP_SELF

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
    echo "Configuration file incorrect, installation aborted"
    rm -f /etc/dhcp/dhcpd.conf
    exit 3
fi

systemctl enable dhcpd
systemctl start dhcpd

iptables -A INPUT -p udp -m udp --sport 67 -j ACCEPT
iptables -A INPUT -p udp -m udp --sport 68 -j ACCEPT
