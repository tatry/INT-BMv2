#include <core.p4>

// TODO:
//	- check MTU at egress
//	- handle replication bits (currently ignored)
//	- insert valid data in some metada fields
//	- more tests

/*************************************************************************
*********************** H E A D E R S  ***********************************
*************************************************************************/
#define PKT_INSTANCE_TYPE_NORMAL 0
#define PKT_INSTANCE_TYPE_INGRESS_CLONE 1
#define PKT_INSTANCE_TYPE_EGRESS_CLONE 2
#define PKT_INSTANCE_TYPE_COALESCED 3
#define PKT_INSTANCE_TYPE_INGRESS_RECIRC 4
#define PKT_INSTANCE_TYPE_REPLICATION 5
#define PKT_INSTANCE_TYPE_RESUBMIT 6

// On BMv2 copying varbit on packet clone is broken...,
// but use headers stack doesn't help
#define INT_METADATA_USE_VARBIT 1
// only for testing for workaround bug
#define INT_METADATA_DONT_COPY_VARBIT 1

#ifdef INT_METADATA_USE_VARBIT
// len is a 8-bit measured in 32-bits words. It contains shim header and int header (12 bytes)
const int INT_MAX_METADATA_SIZE = 32 * (255 - 3);
#else //INT_METADATA_USE_VARBIT
const int INT_MAX_METADATA_STACK_SIZE = (255 - 3);
#endif //INT_METADATA_USE_VARBIT

const bit<8> UDP_PROTOCOL = 0x11;

header int_udp_t
{
	bit<16> srcPort;
	bit<16> dstPort;
	bit<16> len;
	bit<16> checksum;
}

/* INT shim header for TCP/UDP - you could adapt it. It is important that size of this header is exacly 32 bits*/
header int_shim_t
{
	bit<8> int_type;
	bit<8> rsvd1;
	bit<8> len;
	bit<6> dscp;
	bit<2> rsvd2;
}

/* INT header */
header int_header_t
{
	bit<4> ver;
	bit<2> rep;
	bit<1> c;
	bit<1> e;
	bit<1> m;
	bit<7> rsvd1;
	bit<3> rsvd2;
	bit<5> hop_metadata_len;
	bit<8> remaining_hop_cnt;
	
	//bit<4> instruction_mask_0003;
	bit<1> i_switch_id;
	bit<1> i_level1_port_ids;
	bit<1> i_hop_latency;
	bit<1> i_q_occupancy;
	
	//bit<4> instruction_mask_0407;
	bit<1> i_ingress_tstamp;
	bit<1> i_egress_tstamp;
	bit<1> i_level2_port_ids;
	bit<1> i_egress_port_tx_util;
	
	bit<4> instruction_mask_0811;
	
	//bit<4> instruction_mask_1215;
	bit<3> instruction_mask_1214;
	bit<1> i_checksum_complement;
	
	bit<16> rsvd3;
}

// previous metadata - theirs value are not important
header int_prev_metadata_stack_t
{
#ifdef INT_METADATA_USE_VARBIT
	varbit<(INT_MAX_METADATA_SIZE)> prev_metadata;
#else //INT_METADATA_USE_VARBIT
	bit<32> prev_metadata_word;
#endif //INT_METADATA_USE_VARBIT
}

#ifndef INT_METADATA_USE_VARBIT
typedef int_prev_metadata_stack_t[INT_MAX_METADATA_STACK_SIZE] int_prev_metadata_stack_words_t;
#endif //INT_METADATA_USE_VARBIT

/* INT meta-value headers - different header for each value type */
header int_switch_id_t
{
	bit<32> switch_id;
}

header int_level1_port_ids_t
{
	bit<16> ingress_port_id;
	bit<16> egress_port_id;
}

header int_hop_latency_t
{
	bit<32> hop_latency;
}

header int_q_occupancy_t
{
	bit<8> q_id;
	bit<24> q_occupancy;
}

header int_ingress_tstamp_t
{
	bit<32> ingress_tstamp;
}

header int_egress_tstamp_t
{
	bit<32> egress_tstamp;
}

header int_level2_port_ids_t
{
	bit<32> ingress_port_id;
	bit<32> egress_port_id;
}

header int_egress_port_tx_util_t
{
	bit<32> egress_port_tx_util;
}

header int_checksum_complement_t
{
	bit<32> checksum_complement;
}

struct int_headers_t
{
	int_udp_t                   udp; // used to send metadata to a server
	int_shim_t					shim_hdr;
	int_header_t				int_hdr;
	
	int_switch_id_t				switch_id;
	int_level1_port_ids_t		level1_port_ids;
	int_hop_latency_t			hop_latency;
	int_q_occupancy_t			q_occupancy;
	int_ingress_tstamp_t		ingress_tstamp;
	int_egress_tstamp_t			egress_tstamp;
	int_level2_port_ids_t		level2_port_ids;
	int_egress_port_tx_util_t	egress_port_tx_util;
	int_checksum_complement_t	checksum_complement;

#ifdef INT_METADATA_USE_VARBIT
	int_prev_metadata_stack_t	prev_metadata_stack;
#else //INT_METADATA_USE_VARBIT
	int_prev_metadata_stack_words_t	prev_metadata_stack;
#endif //INT_METADATA_USE_VARBIT
}

struct int_packet_metadata_t
{
	bool do_drop_metadata; // If true, please mark packet as NOT containg In-Band Network Telemetry
	bool do_create_header; // If true, please mark packet as containg In-Band Network Telemetry
	
	bool force_redirect; // If true, packet is designed to a server. We cannot change IP addresses
	                     // directly, so it is up to you.
	bit<32> dstIP; // destination IP
	bit<32> srcIP; // source IP
	bit<32> new_payload_size; // size of the redirected payload - You have to truncate redirected packet
	
	bool do_clone_packet; // If true, please clone3 (or similar) packet with metadata to egress
	bit<32> session; // session to clone

	int_headers_t original_headers;
#ifndef INT_METADATA_USE_VARBIT
	bit<8> words_to_read; // only used in parser
#endif //INT_METADATA_USE_VARBIT
}

/*************************************************************************
*********************** P A R S E R  *************************************
*************************************************************************/
error
{
	INTShimLenTooShort,
	INTVersionNotSupported
}

// It is up to user to check if pakcet contains INT header and metadata (if any)
parser int_parser(      packet_in             packet,
                  out   int_headers_t         hdr,
                  inout int_packet_metadata_t meta,
                  inout standard_metadata_t   std_meta)
{
	state start
	{
		transition parse_shim;
	}
	
	state parse_shim
	{
		packet.extract(hdr.shim_hdr);
		verify(hdr.shim_hdr.len >= 3, error.INTShimLenTooShort);
		
		transition parse_int;
	}
#ifdef INT_METADATA_USE_VARBIT
	state parse_int
	{
		// extract main header
		packet.extract(hdr.int_hdr);
		verify(hdr.int_hdr.ver == 1, error.INTVersionNotSupported);
		
		// extract previous metadata
		packet.extract(hdr.prev_metadata_stack, (((bit<32>) hdr.shim_hdr.len) - 3) * 32);
		
		transition accept;
	}
#else //INT_METADATA_USE_VARBIT
	state parse_int
	{
		// extract main header
		packet.extract(hdr.int_hdr);
		verify(hdr.int_hdr.ver == 1, error.INTVersionNotSupported);
		
		meta.words_to_read = hdr.shim_hdr.len - 3;
		
		transition int_read_metadata_word;
	}
	
	state int_read_metadata_word
	{
		packet.extract(hdr.prev_metadata_stack.next);
		meta.words_to_read = meta.words_to_read - 1;
		
		transition select(meta.words_to_read)
		{
			0:	accept;
			default: int_read_metadata_word;
		}
	}
#endif //INT_METADATA_USE_VARBIT
}
/*************************************************************************
*********************** H E L P E R S  ***********************************
*************************************************************************/

#ifndef INT_METADATA_USE_VARBIT
int_prev_metadata_stack_words_t getInvalidStackMetadata()
{
	int_prev_metadata_stack_words_t tmp;
	return tmp;
}
#endif //INT_METADATA_USE_VARBIT

/*************************************************************************
*********************** I N G R E S S  ***********************************
*************************************************************************/
control int_ingress(inout int_headers_t         hdr,
                    inout int_packet_metadata_t meta,
                    inout standard_metadata_t   std_meta)
{
	action create_int_header(bit<8> max_hop_cnt,
                                                bit<1> add_switch_id,
                                                bit<1> add_level1_port_ids,
                                                bit<1> add_hop_latency, 
                                                bit<1> add_q_occupancy, 
                                                bit<1> add_ingress_tstamp, 
                                                bit<1> add_egress_tstamp, 
                                                bit<1> add_level2_port_ids, 
                                                bit<1> add_egress_port_tx_util, 
                                                bit<1> add_checksum_complement)
	{
		meta.do_create_header = true;
		
		hdr.shim_hdr.setValid();
		hdr.shim_hdr.int_type = 0;
		hdr.shim_hdr.rsvd1 = 0;
		hdr.shim_hdr.len = 3;
		hdr.shim_hdr.dscp = 0;
		hdr.shim_hdr.rsvd2 = 0;
		
		hdr.int_hdr.setValid();
		hdr.int_hdr.ver = 1;
		hdr.int_hdr.rep = 0;
		hdr.int_hdr.c = 0;
		hdr.int_hdr.e = 0;
		hdr.int_hdr.m = 0;
		hdr.int_hdr.rsvd1 = 0;
		hdr.int_hdr.rsvd2 = 0;
		hdr.int_hdr.hop_metadata_len = 0;
		hdr.int_hdr.remaining_hop_cnt = max_hop_cnt;
		
		hdr.int_hdr.i_switch_id = add_switch_id;
		hdr.int_hdr.i_level1_port_ids = add_level1_port_ids;
		hdr.int_hdr.i_hop_latency = add_hop_latency;
		hdr.int_hdr.i_q_occupancy = add_q_occupancy;
		hdr.int_hdr.i_ingress_tstamp = add_ingress_tstamp;
		hdr.int_hdr.i_egress_tstamp = add_egress_tstamp;
		hdr.int_hdr.i_level2_port_ids = add_level2_port_ids;
		hdr.int_hdr.i_egress_port_tx_util = add_egress_port_tx_util;
		hdr.int_hdr.instruction_mask_0811 = 0;
		hdr.int_hdr.instruction_mask_1214 = 0;
		hdr.int_hdr.i_checksum_complement = add_checksum_complement;
		hdr.int_hdr.rsvd3 = 0;
	
		hdr.switch_id.setInvalid();
		hdr.level1_port_ids.setInvalid();
		hdr.hop_latency.setInvalid();
		hdr.q_occupancy.setInvalid();
		hdr.ingress_tstamp.setInvalid();
		hdr.egress_tstamp.setInvalid();
		hdr.level2_port_ids.setInvalid();
		hdr.egress_port_tx_util.setInvalid();
		hdr.checksum_complement.setInvalid();
#ifdef INT_METADATA_USE_VARBIT
		hdr.prev_metadata_stack.setInvalid();
#else //INT_METADATA_USE_VARBIT
		hdr.prev_metadata_stack = getInvalidStackMetadata();
#endif //INT_METADATA_USE_VARBIT
	}
	
	table create_on_port
	{
		key =
		{
			std_meta.ingress_port: exact;
		}
		actions =
		{
			create_int_header;
			NoAction;
		}
		
		size = 1024;
		default_action = NoAction();
	}
	
	apply
	{
		meta.do_create_header = false;
		
		if (hdr.int_hdr.isValid())
			return;

		create_on_port.apply();
		
		if (hdr.int_hdr.isValid() == false)
			return;
		
		// calculate hop ML
		if (hdr.int_hdr.i_switch_id == 1)
			hdr.int_hdr.hop_metadata_len = hdr.int_hdr.hop_metadata_len + 1;
		if (hdr.int_hdr.i_level1_port_ids == 1)
			hdr.int_hdr.hop_metadata_len = hdr.int_hdr.hop_metadata_len + 1;
		if (hdr.int_hdr.i_hop_latency == 1)
			hdr.int_hdr.hop_metadata_len = hdr.int_hdr.hop_metadata_len + 1;
		if (hdr.int_hdr.i_q_occupancy == 1)
			hdr.int_hdr.hop_metadata_len = hdr.int_hdr.hop_metadata_len + 1;
		if (hdr.int_hdr.i_ingress_tstamp == 1)
			hdr.int_hdr.hop_metadata_len = hdr.int_hdr.hop_metadata_len + 1;
		if (hdr.int_hdr.i_egress_tstamp == 1)
			hdr.int_hdr.hop_metadata_len = hdr.int_hdr.hop_metadata_len + 1;
		if (hdr.int_hdr.i_level2_port_ids == 1)
			hdr.int_hdr.hop_metadata_len = hdr.int_hdr.hop_metadata_len + 2;
		if (hdr.int_hdr.i_egress_port_tx_util == 1)
			hdr.int_hdr.hop_metadata_len = hdr.int_hdr.hop_metadata_len + 1;
		if (hdr.int_hdr.i_checksum_complement == 1)
			hdr.int_hdr.hop_metadata_len = hdr.int_hdr.hop_metadata_len + 1;
	}
}


/*************************************************************************
************************ E G R E S S  ************************************
*************************************************************************/
control int_insert_metadata(inout int_headers_t         hdr,
                            inout int_packet_metadata_t meta,
                            inout standard_metadata_t   std_meta)
{
	register<bit<32>>(1) switch_id;
	
	action insert_switch_id()
	{
		hdr.switch_id.setValid();
		switch_id.read(hdr.switch_id.switch_id, 0);
	}
	action insert_level1_port_ids()
	{
		hdr.level1_port_ids.setValid();
		hdr.level1_port_ids.ingress_port_id = (bit<16>) std_meta.ingress_port;
		hdr.level1_port_ids.egress_port_id = (bit<16>) std_meta.egress_port;
	}
	action insert_hop_latency()
	{
		hdr.hop_latency.setValid();
		hdr.hop_latency.hop_latency = ((bit<32>) std_meta.egress_global_timestamp) - std_meta.enq_timestamp;
	}
	action insert_q_occupancy()
	{
		hdr.q_occupancy.setValid();
		hdr.q_occupancy.q_id = 8w0xFF;
		hdr.q_occupancy.q_occupancy = (bit<24>) std_meta.enq_qdepth;
	}
	action insert_ingress_tstamp()
	{
		hdr.ingress_tstamp.setValid();
		hdr.ingress_tstamp.ingress_tstamp = (bit<32>) std_meta.ingress_global_timestamp;
	}
	action insert_egress_tstamp()
	{
		hdr.egress_tstamp.setValid();
		hdr.egress_tstamp.egress_tstamp = (bit<32>) std_meta.egress_global_timestamp;
	}
	action insert_level2_port_ids()
	{
		hdr.level2_port_ids.setValid();
		hdr.level2_port_ids.ingress_port_id = 32w0xFF_FF_FF_FF;
		hdr.level2_port_ids.egress_port_id = 32w0xFF_FF_FF_FF;
	}
	action insert_egress_port_tx_util()
	{
		hdr.egress_port_tx_util.setValid();
		hdr.egress_port_tx_util.egress_port_tx_util = 32w0xFF_FF_FF_FF;
	}
	action insert_checksum_complement()
	{
		hdr.checksum_complement.setValid();
		hdr.checksum_complement.checksum_complement = 32w0xFF_FF_FF_FF;
	}
	
	apply
	{
		if (hdr.int_hdr.ver != 1)
			return; // other versions not supported directly
		
		if (hdr.int_hdr.remaining_hop_cnt == 0)
		{
			// exceeded maximum hop count
			hdr.int_hdr.e = 1;
			return;
		}
		hdr.int_hdr.remaining_hop_cnt = hdr.int_hdr.remaining_hop_cnt - 1;
		
		// TODO: check MTU and set m bit if necessery
		
		if (hdr.int_hdr.i_switch_id == 1)
			insert_switch_id();
		if (hdr.int_hdr.i_level1_port_ids == 1)
			insert_level1_port_ids();
		if (hdr.int_hdr.i_hop_latency == 1)
			insert_hop_latency();
		if (hdr.int_hdr.i_q_occupancy == 1)
			insert_q_occupancy();
		if (hdr.int_hdr.i_ingress_tstamp == 1)
			insert_ingress_tstamp();
		if (hdr.int_hdr.i_egress_tstamp == 1)
			insert_egress_tstamp();
		if (hdr.int_hdr.i_level2_port_ids == 1)
			insert_level2_port_ids();
		if (hdr.int_hdr.i_egress_port_tx_util == 1)
			insert_egress_port_tx_util();
		if (hdr.int_hdr.i_checksum_complement == 1)
			insert_checksum_complement();
		
		hdr.shim_hdr.len = hdr.shim_hdr.len + (bit<8>) hdr.int_hdr.hop_metadata_len;
	}
}


control int_egress(inout int_headers_t         hdr,
                   inout int_packet_metadata_t meta,
                   inout standard_metadata_t   std_meta)
{
	register<bit<8>>(4) server_IP;
	register<bit<8>>(4) switch_IP;
	register<bit<16>>(1) server_port;
	register<bit<16>>(1) switch_port;
	
	action drop_int_header(bit<32> session)
	{
		meta.do_drop_metadata = true;
		meta.session = session;
	}
	
	table drop_on_port
	{
		key =
		{
			std_meta.egress_port: exact;
		}
		actions =
		{
			drop_int_header;
			NoAction;
		}
		
		size = 1024;
		default_action = NoAction();
	}
	
	action copy_int_headers(out int_headers_t dst, in int_headers_t src)
	{
		dst.shim_hdr = src.shim_hdr;
		dst.int_hdr = src.int_hdr;
		dst.switch_id = src.switch_id;
		dst.level1_port_ids = src.level1_port_ids;
		dst.hop_latency = src.hop_latency;
		dst.q_occupancy = src.q_occupancy;
		dst.ingress_tstamp = src.ingress_tstamp;
		dst.egress_tstamp = src.egress_tstamp;
		dst.level2_port_ids = src.level2_port_ids;
		dst.egress_port_tx_util = src.egress_port_tx_util;
		dst.checksum_complement = src.checksum_complement;
#ifndef INT_METADATA_DONT_COPY_VARBIT
		dst.prev_metadata_stack = src.prev_metadata_stack; /// BUG: This line causes packet's drop
#endif
	}
	
	apply 
	{
		meta.force_redirect = false;
		meta.do_drop_metadata = false;
		meta.do_clone_packet = false;
		
		/*
		BMv2 on packet clone() copy packet as constructed by the deparser. So
		In-Band Network Telemetry metadata we need to preserve in metadata,
		because original packet cannot contain them (must not be emitted by
		the deparser). Also cloning a non-empty metadata is not supported...
		
		In other words: cloning a packet is buggy in BMv2
		*/
		
		if (std_meta.instance_type == PKT_INSTANCE_TYPE_EGRESS_CLONE)
		{
			if (meta.original_headers.int_hdr.isValid() == false)
				return;
			
			// This is a copy to server, do not insert metadata, only send headers to a serwer
			meta.force_redirect = true;
			
			copy_int_headers(hdr, meta.original_headers);
			
			bit<8> addr1; bit<8> addr2; bit<8> addr3; bit<8> addr4;
			server_IP.read(addr1, 0);
			server_IP.read(addr2, 1);
			server_IP.read(addr3, 2);
			server_IP.read(addr4, 3);
			meta.dstIP = addr1 ++ addr2 ++ addr3 ++ addr4;
			
			switch_IP.read(addr1, 0);
			switch_IP.read(addr2, 1);
			switch_IP.read(addr3, 2);
			switch_IP.read(addr4, 3);
			meta.srcIP = addr1 ++ addr2 ++ addr3 ++ addr4;
			
			hdr.udp.setValid();
			server_port.read(hdr.udp.dstPort, 0);
			switch_port.read(hdr.udp.srcPort, 0);
			hdr.udp.len = 8 + ((bit<16>) hdr.shim_hdr.len) * 4;
			hdr.udp.checksum = 0;
			
			meta.new_payload_size = (bit<32>) hdr.udp.len;
		}
		else
		{
			// Original (TM) packet
			if (hdr.int_hdr.isValid() == false)
				return;
		
			int_insert_metadata.apply(hdr, meta, std_meta);

			drop_on_port.apply();

			if (meta.do_drop_metadata)
			{
				// preserve original metadata and drop them in a packet
				meta.do_clone_packet = true;
				copy_int_headers(meta.original_headers, hdr); // due to bug
			
				hdr.shim_hdr.setInvalid();
				hdr.int_hdr.setInvalid();
		
				hdr.switch_id.setInvalid();
				hdr.level1_port_ids.setInvalid();
				hdr.hop_latency.setInvalid();
				hdr.q_occupancy.setInvalid();
				hdr.ingress_tstamp.setInvalid();
				hdr.egress_tstamp.setInvalid();
				hdr.level2_port_ids.setInvalid();
				hdr.egress_port_tx_util.setInvalid();
				hdr.checksum_complement.setInvalid();
		
#ifdef INT_METADATA_USE_VARBIT
				hdr.prev_metadata_stack.setInvalid();
#else //INT_METADATA_USE_VARBIT
				hdr.prev_metadata_stack = getInvalidStackMetadata();
#endif //INT_METADATA_USE_VARBIT
			}
		}
	} // apply
}


/*************************************************************************
********************** D E P A R S E R  **********************************
*************************************************************************/

control int_deparser(packet_out packet, in int_headers_t hdr)
{
	apply
	{
		packet.emit(hdr.udp);
		packet.emit(hdr.shim_hdr);
		packet.emit(hdr.int_hdr);

		packet.emit(hdr.switch_id);
		packet.emit(hdr.level1_port_ids);
		packet.emit(hdr.hop_latency);
		packet.emit(hdr.q_occupancy);
		packet.emit(hdr.ingress_tstamp);
		packet.emit(hdr.egress_tstamp);
		packet.emit(hdr.level2_port_ids);
		packet.emit(hdr.egress_port_tx_util);
		packet.emit(hdr.checksum_complement);

		packet.emit(hdr.prev_metadata_stack);
	}
}


