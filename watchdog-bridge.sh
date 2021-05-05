#!/bin/bash

# required for bpwd_tst command
modprobe i2c-dev

# Setup the bridge
ip link set enp7s0f0 up
ip link set enp7s0f1 up
ip link add name bypass0 type bridge
ip link set enp7s0f0 master bypass0
ip link set enp7s0f1 master bypass0
brctl setageing bypass0 0
ip link set bypass0 up

# Configure watchdog with a 5 seconds timer (0x5)
bpwd_tst -a 0 -w -d 0x37 -c 0x22 -o 0x5

# Start watchdog
bpwd_tst -a 0 -w -d 0x37 -c 0x24 -o 0x00

# Reset the timer every 2 seconds
echo "Press [CTRL+C] to stop.."
while :
do
	bpwd_tst -a 0 -w -d 0x37 -c 0x24 -o 0x00
	sleep 2
done
