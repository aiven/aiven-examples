# Collect linux distribution
cat /etc/*-release > linux_distribution

# Collect kernel version
uname -r > kernel_version

# Collect CPU metadata
lscpu > cpu_info

# Collect Memory metadata
cat /proc/meminfo > mem_info

# Collect kernel settings
sysctl -a > kernel_settings

# Collect kernel compile options
getconf -a > kernel_compile_options

# Collect all kafka broker configs
./bin/kafka-configs.sh --describe --bootstrap-server <STRIMZI-BOOTSTRAP-SERVER>:<STRIMZI-PORT> --entity-type brokers --all > kafka_broker_configs.txt

# Collect all Consumer Group States from cluster
./bin/kafka-consumer-groups.sh --all-groups --describe --state --bootstrap-server <STRIMZI-BOOTSTRAP-SERVER>:<STRIMZI-PORT> --timeout 180000 > consumer_groups_state.txt