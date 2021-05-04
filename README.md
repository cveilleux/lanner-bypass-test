# Lanner by-pass gen3 review

## Purpose

- Build a gigabit ethernet, transparent network sniffer using a lanner network appliance with built-in network by-pass.
- Demonstrate if, in various failure situations, the network by-pass can reduce or minimize service disruptions.


## Methodology

- We will be using a minimal linux distribution based on Yocto Linux 3.1.7 (dunfell) and linux kernel v5.4.106.
- A transparent linux bridge will be configured so network can freely transit between network ports.
- Test devices will be connected on each ports.
- Link states will be monitored using OS logs and packet loss will be measured using ICMP pings.
- Multiple failure scenarios will be tested:
  - Soft reboot 
  - Hard reboot 
  - Power off using power button
  - Software crash
  - Kernel panic
  - Unexpected power loss

### Network diagram

- NCA-1510D
  - port 0: unused
  - port 1: unused
  - port 2: unused
  - port 3: unused
  - uController with by-pass/watchdog
    - port 4: peerA
    - port 5: peerB

### Explanation

- When the by-pass is ON, peerA and peerB establish a direct ethernet link with each other.
- When the by-pass is OFF, two links must be established:
  - peerA to NCA-1510
  - peerB to NCA-1510
- The linux kernel is pre-configured to act as a transparent bridge (network hub) by forwarding all received frames from one port to the other as-is. 


## Test unit

Our test unit is a NCA-1510D with the following specs:

- Intel® Atom™ **8 Cores** C3758
- 4x RJ45 (intel X553)
- 2x RJ45 (intel I210)
- 1 pair of by-pass (2 premiers ports)
- 1x 260-pin DDR4 2400MHz ECC DIMM, Max. 16GB
- Intel® QuickAssist Technology at 10Gbps
- Intel® AES-NI & TPM Support
- 1x Mini USB Console, 2x USB 3.0
- 1x Mini-PCIe, 1x M.2, 1x Nano SIM Accessibility
- 1x 2.5” HDD/SSD Bay, 1x Onboard EMMC 8GB
- Fanless Design


The unit is sold without RAM, a Crucial 8GiB (CT8G4SFS824A.C8FJ) dimm was installed.

Our linux distribution was installed on a sata SSD and connected using the available SATA data and power cables on the NCA-1510D.


## Lanner bpwd utility

Lanner america provided us with a utility named bpwd version 1.2.9 (dated May 03, 2019) that is used to send commands to the on-board by-pass microcontroller.

This utility is Copyright(c) 2013 Lanner Electronics Inc. and distributed under the GNU General Public License, version 2.

The utility communicates using i2c bus commands to read and change states.

There are 3 supported i2c modes that are chosen at compile time:

- Direct IO (no kernel driver required)
- Lanner driver (sends commands through a lanner developed kernel driver that is not included with the bpwd tool)
- Linux driver (use the mainline linux i2c-dev kernel module available since linux 2.6.15.6

The default mode (linux driver) was used for this experiment.


### Compiling the bpwd_tst binary

```
cd lanner_bpwd-1.2.9
mv Makefile.linux Makefile
make
```

This will compile a `bin/bpwd_tst` binary that can be copied to the test unit filesystem under `/usr/bin`.


## Configuring and persisting by-pass configurations

### Required kernel module

bpwd_tst command requires i2c-dev kernel module to be loaded:

```
modprobe i2c-dev
```

### Settings default configuration

Using the bpwd utility you can read current state of the by-pass:

```
bpwd_tst -a 0 -I -d 0x37
```

The utility will report 4 by-pass available even though the hardware only has one. Attempting to enable by-pass 2, 3 or 4 will have no effect.

The factory defaults of the unit received were:

- Power-off: By-pass on
- Just-on: By-pass off
- Running: By-pass off

For our experiment, we will want the by-pass ON at all times by default. We will then control explicitely when we turn-off the by-pass using a script. The idea is for the hardware to return to a safe default of by-pass ON whenever our script is not working.

```
bpwd_tst -a 0 -w -d 0x37 -c 0x11 -o 0xff
bpwd_tst -a 0 -w -d 0x37 -c 0x12 -o 0xff
bpwd_tst -a 0 -w -d 0x37 -c 0x0B -o 0xff
```

At this point the system was halted and power was removed. Upon rebooting we confirmed that the changes were persisted by reading the state of the by-pass again.


## Sniffing using a transparent bridge

We will use a simple bash script to:

- Setup a linux transparent bridge that turns the 2 network ports controlled by the by-pass into a simple ethernet switch.
- Configure the hardware watchdog 1 to turn the by-pass 1 ON when its countdown timer ends.
- Start the hardware watchdog 1.
- Send regular timer resets to the watchdog in order to prevent the watchdog from tripping, until the script is interruped.

The script is available as `watchdog-bridge.sh` and should be copied to /usr/bin/watchdog-bridge.sh (this path is referenced in the provided systemd unit file).

The script is hard-coded to use `enp7s0f0` and `enp7s0f1` as the 2 network interfaces, which are the network ports controlled by the by-pass in our test unit. These ports were discovered through trial and error.

Our linux distribution is using systemd. The script is launched on boot using the provided systemd unit file.

```
cp watchdog-bridge.service /etc/systemd/system
systemctl daemon-reload
systemctl enable watchdog-bridge
systemctl start watchdog-bridge
```

Once running, we can confirm the linux kernel is bridging the network packets by running tcpdump or tshark on the bridge interface in a seperate terminal:

```
tshark -i bypass0 -l --print
```

From there, you could use any linux tools to sniff, filter, shape or mangle the traffic such a tshark, tcpdump, tc, iptables, nftables, eBPF, etc.


## Test scenarios and results

### Normal operations

Under normal operating conditions, the system will boot and execute the `watchdog-bridge.sh` script.

The by-pass is disabled and linux kernel takes over the network links and ethernet frames.

- We observe a link reset on both peers.
- The link is re-established within 8 to 12 seconds and traffic restarts flowing.


### Soft reboot

We issue a `reboot` command.

 and issue a system reboot.

- The init system proceeds to terminate all running processes including our watchdog script.
- The 5 seconds watchdog timer trips and the by-pass is switched ON.
- We observe a link reset on both peers.
- The link is re-established within 8 to 12 seconds and traffic restarts flowing.


### Hard reboot 

We force an immediate reboot using `/proc/sysrq-trigger`:

```
echo "b" > /proc/sysrq-trigger
```

- This causes an immediate, hard reboot.
- Packet loss occurs immediately for a few seconds
- The by-pass is then switched on
  - It is unknown if the by-pass is reset because of the watchdog timer or normal system boot-up process.
- We observe a link reset on both peers.
- The link is re-established within 8 to 12 seconds and traffic restarts flowing.


### Power off using power button

We turn off the system by holding the power button for 4 seconds.

- This causes an immediate, hard reboot.
- The by-pass is switched on immediately.
- We observe a link reset on both peers.
- The link is re-established within 8 to 12 seconds and traffic restarts flowing.


### Software crash

We send a SIGKILL to our script in order the simulate a crash.

```
ps aux | grep watchdog-bridge.sh
kill -KILL [pid]
```

- The 5 seconds watchdog timer trips and the by-pass is switched ON.
- We observe a link reset on both peers.
- The link is re-established within 8 to 12 seconds and traffic restarts flowing.


### Kernel panic

A kernel panic can be simulated on linux with:

```
echo "c" > /proc/sysrq-trigger
```

- The 5 seconds watchdog timer trips and the by-pass is switched ON.
- We observe a link reset on both peers.
- The link is re-established within 5 seconds and traffic restarts flowing.


### Unexpected power loss

We abruptly disconnect power to the test unit.

- We observe a link reset on both peers.
- The link is re-established within 8 to 12 seconds and traffic restarts flowing.

Reconnecting power after power loss causes the unit to reboot immediately and the by-pass remains on, no packet loss observed.



