#!/bin/bash

source /etc/contrail/agent_param

function pkt_setup () {
    for f in /sys/class/net/$1/queues/rx-*
    do
        q="$(echo $f | cut -d '-' -f2)"
        r=$(($q%32))
        s=$(($q/32))
        ((mask=1<<$r))
        str=(`printf "%x" $mask`)
        if [ $s -gt 0 ]; then
            for ((i=0; i < $s; i++))
            do
                str+=,00000000
            done
        fi
        echo $str > $f/rps_cpus
    done
}

function insert_vrouter() {
    grep $kmod /proc/modules 1>/dev/null 2>&1
    if [ $? != 0 ]; then
        modprobe $kmod
        if [ $? != 0 ]
        then
            echo "$(date) : Error inserting vrouter module"
            return 1
        fi

        if [ -f /sys/class/net/pkt1/queues/rx-0/rps_cpus ]; then
            pkt_setup pkt1
        fi
        if [ -f /sys/class/net/pkt2/queues/rx-0/rps_cpus ]; then
            pkt_setup pkt2
        fi
    fi

    # check if vhost0 is not present, then create vhost0 and $dev
    if [ ! -L /sys/class/net/vhost0 ]; then
        echo "$(date): Creating vhost interface: $DEVICE."
        # for bonding interfaces
        loops=0
        while [ ! -f /sys/class/net/$dev/address ]
        do
            sleep 1
            loops=$(($loops + 1))
            if [ $loops -ge 60 ]; then
                echo "Unable to look at /sys/class/net/$dev/address"
                return 1
            fi
        done

        DEV_MAC=$(cat /sys/class/net/$dev/address)
        vif --create $DEVICE --mac $DEV_MAC
        if [ $? != 0 ]; then
            echo "$(date): Error creating interface: $DEVICE"
        fi


        echo "$(date): Adding $dev to vrouter"
        DEV_MAC=$(cat /sys/class/net/$dev/address)
        vif --add $dev --mac $DEV_MAC --vrf 0 --vhost-phys --type physical
        if [ $? != 0 ]; then
            echo "$(date): Error adding $dev to vrouter"
        fi

        vif --add $DEVICE --mac $DEV_MAC --vrf 0 --type vhost --xconnect $dev
        if [ $? != 0 ]; then
            echo "$(date): Error adding $DEVICE to vrouter"
        fi
    fi
    return 0
}

