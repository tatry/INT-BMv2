#!/usr/bin/env python

#source: https://github.com/p4lang/behavioral-model/blob/master/mininet/1sw_demo.py

from mininet.net import Mininet
from mininet.topo import Topo
from mininet.log import setLogLevel, info
from mininet.cli import CLI
from mininet.node import OVSBridge

from p4_mininet import P4Switch, P4Host

import argparse

parser = argparse.ArgumentParser(description='In-Band Network Telemetry demo')
parser.add_argument('--behavioral-exe', help='Path to behavioral executable',
	type=str, action="store", required=False, default='/usr/local/bin/simple_switch')
parser.add_argument('--json', help='Path to JSON config file', type=str, action="store", required=True)
parser.add_argument('--server-exe', help='Path to executable to receive INT metadata',
	type=str, action="store", required=False)
parser.add_argument('--thrift-port', help='Thrift server port for table updates',
	type=int, action="store", default=9090)
#parser.add_argument('--mode', choices=['l2', 'l3'], type=str, default='l3')
#parser.add_argument('--pcap-dump', help='Dump packets on interfaces to pcap files',
#	type=str, action="store", required=False, default=False)

args = parser.parse_args()

class INTDemoNetTopo(Topo):
	""" Demononstration and testing topology for In-Band Network Telemetry
	Genereted topology is as follow:
	
	    h1 --- s1
	          / |\
	         /  | \    +--- h3
	        /   |  \  /  
	h2 --- s2 --+-- s3 --- h4
	        \   |   |
	         +- s4 -+
	             |
	            h5
	
	Where:
	s1, s2, s3 are regular P4 switches (here BMv2)
	s4 is multiplexing switch designed to forward telemetry metadata
	h1, h2, h3, h4 are regular IPv4 hosts
	h5 is a server receiving INT metadata
	"""
	def __init__(self, sw_path, json_path, thrift_port, pcap_dump, **opts):
		# Initialize topology and default options
		Topo.__init__(self, **opts)
		
		self.num_hosts = 5
		self.num_switches = 4
		
		# Add switches
		switch = []
		for s in xrange(self.num_switches):
			switch.append(
				self.addSwitch(
					's%d' % (s + 1),
					sw_path = sw_path,
					json_path = json_path,
					thrift_port = thrift_port + s,
					pcap_dump = pcap_dump,
					enable_debugger = True
				)
			)
		self.switch = switch
		
		# Add hosts
		host = []
		for h in xrange(self.num_hosts):
			host.append(
				self.addHost(
					'h%d' % (h + 1),
					ip = "10.0.%d.10/24" % h,
					mac = '00:0A:00:00:00:%02x' % h
				)
			)
		self.host = host
		
		# Add links
		self.addLink(switch[0], switch[1])
		self.addLink(switch[1], switch[2])
		self.addLink(switch[2], switch[0])
		
		self.addLink(switch[0], switch[3])
		self.addLink(switch[1], switch[3])
		self.addLink(switch[2], switch[3])
		
		self.addLink(host[0], switch[0])
		self.addLink(host[1], switch[1])
		self.addLink(host[2], switch[2])
		self.addLink(host[3], switch[2])
		self.addLink(host[4], switch[3])

def main():
	topo = INTDemoNetTopo(
		args.behavioral_exe,
		args.json,
		args.thrift_port,
		False #args.pcap_dump,
	)
	net = Mininet(
		topo = topo,
		host = P4Host,
		switch = P4Switch,
		#switch = OVSBridge,
		controller = None
	)
	
	#net.configLinkStatus(topo.switch[2], topo.switch[0], 'down')
	#net.configLinkStatus(topo.switch[1], topo.switch[3], 'down')
	#net.configLinkStatus(topo.switch[2], topo.switch[3], 'down')
	net.start()

	switch_mac = ["00:aa:bb:00:00:%02x" % n for n in xrange(topo.num_hosts)]
	switch_addr = ["10.0.%d.1" % n for n in xrange(topo.num_hosts)]

	for n in xrange(topo.num_hosts):
		h = net.get('h%d' % (n + 1))
		#	if mode == "l2":
		#	h.setDefaultRoute("dev eth0")
		#	else:
		h.setARP(switch_addr[n], switch_mac[n])
		h.setDefaultRoute("dev eth0 via %s" % switch_addr[n])

	#for n in xrange(topo.num_hosts):
	#	h = net.get('h%d' % (n + 1))
	#	h.describe()
	
	# Increase MTU on inter-switch links in order to hadle default MTU to host and INT metadata
	# (max 1024 Bytes) without fragmentation. Set MTU to 2524
	mtu = 1500 + 1024
	for n in xrange (topo.num_switches - 1):
		s = net.get('s%s' % (n + 1))
		s.cmd('ip link set dev s%s-eth1 mtu %d' % ((n + 1), mtu))
		s.cmd('ip link set dev s%s-eth2 mtu %d' % ((n + 1), mtu))

	CLI(net)
	net.stop()

if __name__ == '__main__':
    setLogLevel( 'info' )
    main()

