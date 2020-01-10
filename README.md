# INT-BMv2
In-Band Network Telemetry for BMv2 P4 switch

## Getting started

1.	Install dependences:
	- [Mininet](http://mininet.org/download/)
	- [BMv2](https://github.com/p4lang/behavioral-model)
	- [p4c](https://github.com/p4lang/p4c)
	- Other packages not installed by default: ethtool, xterm

2.	Compile code:
	```bash
	p4c --target bmv2-v1model --std p4-16 switch.p4
	```
	This will produce `switch.json` file needed for BMv2.

3.	Setting up test network:

	```bash
	sudo python run/demo_net.py --json switch.json
	```
	In other terminal set up rules forwarding rules:
	```bash
	run/run_forwarding.sh
	```
	And set up rules for In-Band Network Telemetry:
	```bash
	run/run_int.sh
	```
	Now you can use the standard mininet CLI in the first terminal.

## Remarks
- INT metadata is placed behind IP header. So, metrics are collected also for ICMP packets.
- IP packets with metadata are not valid, because field totalLen in IP header is not updated when adding metadata.
- Probably there is a bug in BMv2. Use of field with type `varbit` in metadata when cloning packet cause that only one packet is forwarded. Others are dropped. As a workaround that, valid metrics are only from last switch and the rest are junk data derived from upper layers headers and data.
