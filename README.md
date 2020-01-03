# INT-BMv2
In-Band Network Telemetry for BMv2 P4 switch

Compilation:
p4c --target bmv2-v1model --std p4-16 switch.p4

Setting up network:
sudo python run/demo_net.py --json switch.json
In other terminal set up rules forwarding rules:
run/run_forwarding.sh
And set rules for In-Band Network Telemetry:
run/run_int.sh
