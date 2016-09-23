#!/usr/bin/env sh

if [ -z $1 ] || [ -z $2 ]; then
    echo "$0 <domain_name> <interface>"
    exit 1
fi

DOMAIN_NAME=$1
INTERFACE_IP=`ip addr show dev $2 | awk '/inet\s/{print $2}' | awk -F/ '{print $1}'`
REV_SUBNET=$(echo $INTERFACE_IP | awk -F. '{for (i=NF-1; i>0; --i) printf "%s%s", $i, (i<NF-2 ? "" : ".")}')

yum install bind bind-utils -y

sed -i "s/\(recursion\s*\)\w.*$/\1yes;/g" /etc/named.conf
sed -i "s/\(dnssec-validation\s*\)\w.*$/\1no;/g" /etc/named.conf
sed -i '/options/a\ \tforwarders {\n\t\t8.8.8.8;\n\t};' /etc/named.conf
sed -i '/^zone\s"."/ i zone '$REV_SUBNET'.in-addr.arpa" {\n\ttype master;\n\tfile "db.'$REV_SUBNET'";\n};' /etc/named.conf
sed -i '/^zone\s'$REV_SUBNET'/ i zone "'$DOMAIN_NAME'" {\n\ttype master;\n\tfile "db.'$DOMAIN_NAME'";\n};\n' /etc/named.conf

echo "\$ORIGIN $DOMAIN_NAME.
\$TTL 1W
@               IN SOA          ns.cloud.local.   root.$DOMAIN_NAME. (
                                1              ; serial (d. adams)
                                2D              ; refresh
                                4H              ; retry
                                6W              ; expiry
                                1W )            ; minimum

@               IN NS           ns.$DOMAIN_NAME.
@               IN AAAA         ::1
ns              IN A            $INTERFACE_IP" > /var/named/db.$DOMAIN_NAME
/usr/sbin/named-checkzone $DOMAIN_NAME /var/named/db.$DOMAIN_NAME
if [ ! 0 = $? ]; then
    echo "Zone configure failed:" $DOMAIN_NAME ". Installation abort"
    exit 1
fi;

echo "\$ORIGIN $REV_SUBNET.in-addr.arpa.
\$TTL 1W
@               IN SOA          ns.$DOMAIN_NAME. root.$DOMAIN_NAME. (
                                1              ; serial (d. adams)
                                2D              ; refresh
                                4H              ; retry
                                6W              ; expiry
                                1W )            ; minimum

               IN NS           ns.$DOMAIN_NAME.
1               IN PTR          ns" > /var/named/db.$REV_SUBNET
/usr/sbin/named-checkzone $REV_SUBNET.in-addr.arpa /var/named/db.$REV_SUBNET
if [ ! 0 = $? ]; then
    echo "Zone configure failed:" $REV_SUBNET ". Installation abort"
    exit 1
fi;

if [ -f "/etc/dhcp/dhcpd.conf" ]; then
    cat /etc/dhcp/dhcpd.conf
fi;

systemctl enable named

iptables -A INPUT -p udp -m udp --sport 53 -j ACCEPT
iptables -A INPUT -p udp -m udp --dport 53 -j ACCEPT