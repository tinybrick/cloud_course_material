#!/usr/bin/env bash

if [[ -z $1 ]]; then
    echo "$0 <interface>"
    exit 1
fi

install_dhcp $1


function install_dhcp {
    iptables -A INPUT -p udp -m udp --sport 67 -j ACCEPT
    iptables -A INPUT -p udp -m udp --sport 68 -j ACCEPT

#    yum install -y dhcp

    yes | cp /usr/lib/systemd/system/dhcpd.service /etc/systemd/system/
    sed -i 's/\-\-no\-pid/$1/g' /etc/systemd/system/dhcpd.service

    DHCP_IP_SELF=172.16.0.1

    SUBNET=172.16.0.0
    NET_MASK=255.255.255.0
    BROADCAST_ADDRESS=172.16.0.255
    DHCP_RANGE_FROM=172.16.0.150
    DHCP_RANGE_TO=172.16.0.250
    DHCP_OPTION_ROUTES=$DHCP_IP_SELF
    DHCP_DOMAIN_NAME_SERVERS="$DHCP_IP_SELF, 8.8.8.8"
    DOMAIN_NAME=cloud.local.

    MAC_ADDRESS=`ip link show $0 | awk '/link\/ether/{print $2}'`
    REV_SUBNET=$(echo $SUBNET | awk -F. '{for (i=NF-1; i>0; --i) printf "%s%s", $i, (i<NF-2 ? "" : ".")')

    echo "key \"rndc-key\" {
            algorithm hmac-md5;
            secret \"/y0Bc7NXafpcCkDrwxhep9XmVtm8Btg9XOOHWYY4DkmjriMr1Rf87Mq0AyEsVquAlknA+btf4mYIUVqr8FGO2g==\";
    };

    default-lease-time 600;
    max-lease-time 7200;
    ddns-updates on;
    ddns-update-style interim;
    update-static-leases on;
    subnet $SUBNET netmask $NET_MASK {
      range $DHCP_RANGE_FROM $DHCP_RANGE_TO
      option routers $DHCP_OPTION_ROUTES;
      option domain-name-servers $DHCP_DOMAIN_NAME_SERVERS;
      option domain-name \"$DOMAIN_NAME\";
      option broadcast-address $BROADCAST_ADDRESS;
      ddns-domainname \"$DOMAIN_NAME.\";
      ddns-rev-domainname \"in-addr.arpa.\";
      host self {
        hardware ethernet $MAC_ADDRESS;
        fixed-address $DHCP_IP_SELF;
      }
    }
    allow unknown-clients;
    use-host-decl-names on;
    zone cloud.local. {
      primary $DHCP_IP_SELF; # This server is the primary DNS server for the zone
      key rndc-key;
    }
    zone $REV_SUBNET.in-addr.arpa. {
      primary $DHCP_IP_SELF; # This server is the primary reverse DNS for the zone
      key rndc-key;
    }" > /etc/dhcp/dhcpd.conf

#    systemctl --system daemon-reload
#    systemctl restart dhcpd
}

function install_ddns {
    iptables -A INPUT -p udp -m udp --sport 53 -j ACCEPT
    iptables -A INPUT -p udp -m udp --dport 53 -j ACCEPT

    yum install bind bind-utils -y
}