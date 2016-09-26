#!/usr/bin/env sh
################################################################################
# Run command:
#  $ sudo curl https://raw.githubusercontent.com/tinybrick/cloud_course_material/master/course1/install_bind.sh | bash /dev/stdin [interface] [domain_name]
#

if [ -z $1 ] || [ -z $2 ]; then
    echo "$0 [interface] [domain_name]"
    exit 1
fi

update_or_append() {
    if grep -q "$2" $1
    then
        sed -i "s/\($2\s*\)\w.*/\1$3/g" $1
    else
        sed -i "\$a$2 $3" $1
    fi
}


append_if_not_exist() {
    if grep -Fq "$3" $1
    then
        echo "$3 is found, not gonna insert again"
    else
        sed -i "/$2/a\ $3" $1
    fi
}

insert_if_not_exist() {
    if grep -Fq "$3" $1
    then
        echo "$3 is found, not gonna insert again"
    else
        sed -i "/$2/i$3" $1
    fi
}

NAMED_HOME=/var/named
NAMED_CONFIG_FILE=/etc/named.conf
yes | cp $NAMED_CONFIG_FILE $NAMED_CONFIG_FILE.bak

INTERFACE=$1
DOMAIN_NAME=$2
SUPERIOR_DNS=8.8.8.8

INTERFACE_IP=`ip addr show dev $INTERFACE | awk '/inet\ /{print $2}' | awk -F/ '{print $1}'`
if [ -z $INTERFACE_IP ]; then
    echo "Cann't get IP address. installation aborted"
    exit 2
fi

REV_SUBNET=$(echo $INTERFACE_IP | awk -F. '{for (i=NF-1; i>0; --i) printf "%s%s", $i, (i<NF-2 ? "" : ".")}')
IP_POSITION=$(echo $INTERFACE_IP | awk -F. '{printf $4}')

yum install bind bind-utils -y
if [ ! 0 = $? ]; then
    echo "BIND9 installation failed"
    exit 3
fi

update_or_append $NAMED_CONFIG_FILE "recursion" "yes;"
update_or_append $NAMED_CONFIG_FILE "dnssec-validation" "no;"
append_if_not_exist $NAMED_CONFIG_FILE "options {" "\tforwarders {\n\t\t$SUPERIOR_DNS;\n\t};"
insert_if_not_exist $NAMED_CONFIG_FILE "^zone\s\".\"" "zone \"$REV_SUBNET.in-addr.arpa\" {\n\ttype master;\n\tfile \"db.$REV_SUBNET\";\n};\n"
insert_if_not_exist $NAMED_CONFIG_FILE "^zone\s\"$REV_SUBNET" "zone \"$DOMAIN_NAME\" {\n\ttype master;\n\tfile \"db.$DOMAIN_NAME\";\n};\n"

/usr/sbin/named-checkconf $NAMED_CONFIG_FILE
if [ ! 0 = $? ]; then
    cat $NAMED_CONFIG_FILE
    echo $NAMED_CONFIG_FILE " file contains error"
    yes | cp $NAMED_CONFIG_FILE.bak $NAMED_CONFIG_FILE
    exit 4
fi;

echo "\$ORIGIN $DOMAIN_NAME.
\$TTL 1W
@               IN SOA          ns.cloud.local.   root.$DOMAIN_NAME. (
                                1              ; serial (d. adams)
                                2D              ; refresh
                                4H              ; retry
                                6W              ; expiry
                                1W )            ; minimum

@               IN NS           ns.$DOMAIN_NAME.
@               IN AAAA         ::$IP_POSITION
ns              IN A            $INTERFACE_IP" > $NAMED_HOME/db.$DOMAIN_NAME
/usr/sbin/named-checkzone $DOMAIN_NAME $NAMED_HOME/db.$DOMAIN_NAME
if [ ! 0 = $? ]; then
    echo "Zone configure failed:" $DOMAIN_NAME ". Installation abort"
    exit 5
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
$IP_POSITION               IN PTR          ns" > $NAMED_HOME/db.$REV_SUBNET
/usr/sbin/named-checkzone $REV_SUBNET.in-addr.arpa $NAMED_HOME/db.$REV_SUBNET
if [ ! 0 = $? ]; then
    echo "Zone configure failed:" $REV_SUBNET ". Installation abort"
    exit 6
fi;

echo "Set default DNS to $INTERFACE_IP"
if [ -f "/etc/dhcp/dhcpd.conf" ]; then
    sed -i "s/\(option\sdomain-name-servers\s*\)\w.*$/\1$INTERFACE_IP;/g" /etc/dhcp/dhcpd.conf
fi;

systemctl enable named
systemctl restart dhcpd
systemctl start named

iptables -A INPUT -p udp -m udp --sport 53 -j ACCEPT
iptables -A INPUT -p udp -m udp --dport 53 -j ACCEPT

echo "DNS server install success"