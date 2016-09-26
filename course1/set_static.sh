#!/usr/bin/env bash
##################################
# Run command:
#  $ sudo curl https://raw.githubusercontent.com/tinybrick/cloud_course_material/master/course1/set_static.sh | bash /dev/stdin [interface] [ip] [net_mask]
#

if [[ -z $3 ]]; then
    echo "$0 [interface] [ip] [net_mask_short]"
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

update_or_append() {
    if grep -q "$2" $1
    then
        sed -i "s/\($2=\)\w.*/\1$3/g" $1
    else
        sed  -i "\$a$2=$3" $1
    fi
}

CONFIG_FILE_PATH=/etc/sysconfig/network-scripts
CONFIG_FILE_PREFIX=ifcfg

IP_ADDR=$2
NET_MASK=$(netmask $3)
SUBNET=$(get_subnet $IP_ADDR $3)
BROADCAST=$(broadcast $IP_ADDR $3)

echo "Setup interface $1"
update_or_append $CONFIG_FILE_PATH/$CONFIG_FILE_PREFIX-$1 "BOOTPROTO" "static"
update_or_append $CONFIG_FILE_PATH/$CONFIG_FILE_PREFIX-$1 "IPADDR" "$IP_ADDR"
update_or_append $CONFIG_FILE_PATH/$CONFIG_FILE_PREFIX-$1 "NETMASK" "$NET_MASK"
update_or_append $CONFIG_FILE_PATH/$CONFIG_FILE_PREFIX-$1 "NETWORK" "$SUBNET"
update_or_append $CONFIG_FILE_PATH/$CONFIG_FILE_PREFIX-$1 "BROADCAST" "$BROADCAST"

systemctl restart network
ip addr show $1
echo "Configure is done."