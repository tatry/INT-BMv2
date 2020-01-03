#!/bin/bash

switch_CLI=simple_switch_CLI

# Switch s1
$switch_CLI --thrift-port 9090 << EOF
table_set_default MyIngress.ipv4_lpm MyIngress.drop
table_add MyIngress.ipv4_lpm MyIngress.ipv4_forward_host 10.0.0.10/32 => 00:aa:bb:00:00:00 00:0A:00:00:00:00 4
table_add MyIngress.ipv4_lpm MyIngress.ipv4_forward 10.0.4.10/32 => 3
table_add MyIngress.ipv4_lpm MyIngress.ipv4_forward 10.0.0.0/16 => 1
EOF

# Switch s2
$switch_CLI --thrift-port 9091 << EOF
table_set_default MyIngress.ipv4_lpm MyIngress.drop
table_add MyIngress.ipv4_lpm MyIngress.ipv4_forward_host 10.0.1.10/32 => 00:aa:bb:00:00:01 00:0A:00:00:00:01 4
table_add MyIngress.ipv4_lpm MyIngress.ipv4_forward 10.0.0.10/32 => 1
table_add MyIngress.ipv4_lpm MyIngress.ipv4_forward 10.0.4.10/32 => 3
table_add MyIngress.ipv4_lpm MyIngress.ipv4_forward 10.0.0.0/16 => 2
EOF

# Switch s3
$switch_CLI --thrift-port 9092 << EOF
table_set_default MyIngress.ipv4_lpm MyIngress.drop
table_add MyIngress.ipv4_lpm MyIngress.ipv4_forward_host 10.0.2.10/32 => 00:aa:bb:00:00:02 00:0A:00:00:00:02 4
table_add MyIngress.ipv4_lpm MyIngress.ipv4_forward_host 10.0.3.10/32 => 00:aa:bb:00:00:03 00:0A:00:00:00:03 5
table_add MyIngress.ipv4_lpm MyIngress.ipv4_forward 10.0.4.10/32 => 3
table_add MyIngress.ipv4_lpm MyIngress.ipv4_forward 10.0.0.0/16 => 1
EOF

# Switch s4
$switch_CLI --thrift-port 9093 << EOF
table_set_default MyIngress.ipv4_lpm MyIngress.drop
table_add MyIngress.ipv4_lpm MyIngress.ipv4_forward_host 10.0.4.10/32 => 00:aa:bb:00:00:04 00:0A:00:00:00:04 4
table_add MyIngress.ipv4_lpm MyIngress.ipv4_forward 10.0.0.10/32 => 1
table_add MyIngress.ipv4_lpm MyIngress.ipv4_forward 10.0.1.10/32 => 2
table_add MyIngress.ipv4_lpm MyIngress.ipv4_forward 10.0.0.0/16 => 3
EOF

#fg
