#!/usr/bin/env bash

if [[ -z $1 ]]; then
    echo "$0 <domain_name>"
    exit 1
fi

yum install bind bind-utils -y

sed -i "s/\(recursion\s*\)\w.*$/\1yes;/g" /etc/named.conf
sed -i "s/\(dnssec-validation\s*\)\w.*$/\1no;/g" /etc/named.conf
sed -i '/options/a\ \tforwarders {\n\t\t8.8.8.8;\n\t\t192.168.0.1;\n\t\};' /etc/named.conf
sed -i '/^zone/ i zone "cloud.local" {\n\ttype master;\n\tfile '"db.$1"';\n};\n' /etc/named.conf

iptables -A INPUT -p udp -m udp --sport 53 -j ACCEPT
iptables -A INPUT -p udp -m udp --dport 53 -j ACCEPT