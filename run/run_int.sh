#!/bin/bash

switch_CLI=simple_switch_CLI

# Switch s1
$switch_CLI --thrift-port 9090 << EOF
table_add int_ingress.create_on_port int_ingress.create_int_header 4 => 32 1 1 1  1 0 1  0 0 0
table_add int_egress.drop_on_port int_egress.drop_int_header 3 => 25
table_add int_egress.drop_on_port int_egress.drop_int_header 4 => 25
register_write int_insert_metadata.switch_id 0 1
register_write int_egress.server_IP 0 10
register_write int_egress.server_IP 1 0
register_write int_egress.server_IP 2 4
register_write int_egress.server_IP 3 10
register_write int_egress.switch_IP 0 10
register_write int_egress.switch_IP 1 10
register_write int_egress.switch_IP 2 1
register_write int_egress.switch_IP 3 10
register_write int_egress.server_port 0 9500
register_write int_egress.switch_port 0 121
mirroring_add 25 3
EOF

# Switch s2
$switch_CLI --thrift-port 9091 << EOF
table_add int_ingress.create_on_port int_ingress.create_int_header 4 => 32 1 1 1  1 0 1  0 0 0
table_add int_egress.drop_on_port int_egress.drop_int_header 3 => 25
table_add int_egress.drop_on_port int_egress.drop_int_header 4 => 25
register_write int_insert_metadata.switch_id 0 2
EOF

# Switch s3
$switch_CLI --thrift-port 9092 << EOF
table_add int_ingress.create_on_port int_ingress.create_int_header 4 => 32 1 1 1  1 0 1  0 0 0
table_add int_ingress.create_on_port int_ingress.create_int_header 5 => 32 1 1 1  1 0 1  0 0 0
table_add int_egress.drop_on_port int_egress.drop_int_header 3 => 25
table_add int_egress.drop_on_port int_egress.drop_int_header 4 => 25
table_add int_egress.drop_on_port int_egress.drop_int_header 5 => 25
register_write int_insert_metadata.switch_id 0 3
EOF

# Switch s4

