/* -*- P4_16 -*- */

// based on:
// - https://github.com/p4lang/tutorials/blob/master/exercises/basic/solution/basic.p4
// - https://github.com/p4lang/tutorials/blob/master/exercises/mri/solution/mri.p4

#include <core.p4>
#include <v1model.p4>

#include "int_primitives.p4"

const bit<16> TYPE_IPV4 = 0x800;
const bit<8> DSCP_INT = 0x17;

/*************************************************************************
*********************** H E A D E R S  ***********************************
*************************************************************************/

typedef bit<9>  egressSpec_t;
typedef bit<48> macAddr_t;
typedef bit<32> ip4Addr_t;

header ethernet_t
{
	macAddr_t dstAddr;
	macAddr_t srcAddr;
	bit<16>   etherType;
}

header ipv4_t
{
	bit<4>    version;
	bit<4>    ihl;
	bit<8>    diffserv;
	bit<16>   totalLen;
	bit<16>   identification;
	bit<3>    flags;
	bit<13>   fragOffset;
	bit<8>    ttl;
	bit<8>    protocol;
	bit<16>   hdrChecksum;
	ip4Addr_t srcAddr;
	ip4Addr_t dstAddr;
}

struct metadata
{
	int_packet_metadata_t int_metadata;
}

struct headers
{
	ethernet_t    ethernet;
	ipv4_t        ipv4;
	int_headers_t int_headers;
}

/*************************************************************************
*********************** P A R S E R  ***********************************
*************************************************************************/
error
{
	IPHeaderTooShort,
	IPUnsupportedOptionLen,
	IPUnsupportedOptionType
}

parser MyParser(packet_in packet,
                out headers hdr,
                inout metadata meta,
                inout standard_metadata_t standard_metadata)
{

	state start
	{
		transition parse_ethernet;
	}
	
	state parse_ethernet
	{
		packet.extract(hdr.ethernet);
		transition select(hdr.ethernet.etherType)
		{
			TYPE_IPV4:	parse_ipv4;
			default:	accept;
		}
	}
	
	state parse_ipv4
	{
		packet.extract(hdr.ipv4);
		transition select(hdr.ipv4.diffserv) 
		{
			DSCP_INT: parse_int;
			default: accept;
		}
	}
	
	state parse_int
	{
		int_parser.apply(packet, hdr.int_headers, meta.int_metadata, standard_metadata);
		
		transition accept;
	}
}


/*************************************************************************
************   C H E C K S U M    V E R I F I C A T I O N   *************
*************************************************************************/

control MyVerifyChecksum(inout headers hdr, inout metadata meta)
{   
	apply {  }
}


/*************************************************************************
**************  I N G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

control MyIngress(inout headers hdr,
                  inout metadata meta,
                  inout standard_metadata_t standard_metadata) 
{
	action drop()
	{
		mark_to_drop(standard_metadata);
	}

	action ipv4_forward(egressSpec_t port)
	{
		standard_metadata.egress_spec = port;
		hdr.ipv4.ttl = hdr.ipv4.ttl - 1;
	}

	action ipv4_forward_host(macAddr_t srcAddr, macAddr_t dstAddr, egressSpec_t port)
	{
		standard_metadata.egress_spec = port;
		hdr.ethernet.srcAddr = srcAddr;
		hdr.ethernet.dstAddr = dstAddr;
		hdr.ipv4.ttl = hdr.ipv4.ttl - 1;
	}

	table ipv4_lpm
	{
		key =
		{
			hdr.ipv4.dstAddr: lpm;
		}
		actions =
		{
			ipv4_forward;
			ipv4_forward_host;
			drop;
			NoAction;
		}
		
		size = 1024;
		default_action = NoAction();
	}

	apply 
	{
		if (hdr.ipv4.isValid() && hdr.ipv4.ttl > 0)
		{
			ipv4_lpm.apply();
		
			int_ingress.apply(hdr.int_headers, meta.int_metadata, standard_metadata);
			if (meta.int_metadata.do_create_header)
			{
				// INT headers has been created, but IP header was not prepared
				hdr.ipv4.diffserv = DSCP_INT;
			}
		}
	}
}

/*************************************************************************
****************  E G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

control MyEgress(inout headers hdr,
                 inout metadata meta,
                 inout standard_metadata_t standard_metadata)
{
	apply
	{
		int_egress.apply(hdr.int_headers, meta.int_metadata, standard_metadata);
		
		if (meta.int_metadata.do_drop_metadata)
		{
			hdr.ipv4.diffserv = 0;
		}
		
		if (meta.int_metadata.force_redirect)
		{
			//hdr.ipv4.dstAddr = 8w10 ++ 8w0 ++ 8w4 ++ 8w10;
			hdr.ipv4.dstAddr = meta.int_metadata.dstIP;
			hdr.ipv4.srcAddr = meta.int_metadata.srcIP;
			hdr.ipv4.protocol = UDP_PROTOCOL;
			
			hdr.ipv4.totalLen = ((bit<16>) hdr.ipv4.ihl) * 4;
			hdr.ipv4.totalLen = hdr.ipv4.totalLen + ((bit<16>) meta.int_metadata.new_payload_size);
			truncate(((bit<32>) hdr.ethernet.minSizeInBytes()) + ((bit<32>) hdr.ipv4.totalLen));
		}
		
		if (meta.int_metadata.do_clone_packet)
		{
			clone3<metadata>(CloneType.E2E, meta.int_metadata.session, meta);
		}
	}
}

/*************************************************************************
*************   C H E C K S U M    C O M P U T A T I O N   **************
*************************************************************************/

control MyComputeChecksum(inout headers hdr, inout metadata meta)
{
	apply
	{
		update_checksum(
			hdr.ipv4.isValid(),
			{
				hdr.ipv4.version,
				hdr.ipv4.ihl,
				hdr.ipv4.diffserv,
				hdr.ipv4.totalLen,
				hdr.ipv4.identification,
				hdr.ipv4.flags,
				hdr.ipv4.fragOffset,
				hdr.ipv4.ttl,
				hdr.ipv4.protocol,
				hdr.ipv4.srcAddr,
				hdr.ipv4.dstAddr
			},
			hdr.ipv4.hdrChecksum,
			HashAlgorithm.csum16
		);
	}
}


/*************************************************************************
***********************  D E P A R S E R  *******************************
*************************************************************************/

control MyDeparser(packet_out packet, in headers hdr)
{
	apply
	{
		packet.emit(hdr.ethernet);
		packet.emit(hdr.ipv4);
		int_deparser.apply(packet, hdr.int_headers);
	}
}

/*************************************************************************
***********************  S W I T C H  *******************************
*************************************************************************/

V1Switch(
	MyParser(),
	MyVerifyChecksum(),
	MyIngress(),
	MyEgress(),
	MyComputeChecksum(),
	MyDeparser()
) main;

