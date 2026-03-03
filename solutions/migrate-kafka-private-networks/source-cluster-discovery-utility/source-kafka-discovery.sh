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
./bin/kafka-configs.sh --describe --bootstrap-server <SOURCE-SERVER>:<SOURCE-PORT> --entity-type brokers --all > kafka_broker_configs.txt

#Collect all Consumer Groups from cluster
./kafka-consumer-groups.sh --all-groups --describe --bootstrap-server <SOURCE-SERVER>:<SOURCE-PORT> --timeout 180000 > consumer_groups_source.txt

# Collect all Consumer Group States from cluster
./bin/kafka-consumer-groups.sh --all-groups --describe --state --bootstrap-server <SOURCE-SERVER>:<SOURCE-PORT> --timeout 180000 > consumer_groups_state_source.txt

# Collect all Topic Details from Cluster
./bin/kafka-topics.sh --describe --bootstrap-server <SOURCE-SERVER>:<SOURCE-PORT> --timeout 180000 > topics_list_source.txt

# Collect only Topic names from Cluster -- necessary for diskless topic creation in destination cluster
./bin/kafka-topics.sh \
--list \
--bootstrap-server <SOURCE-SERVER>
 > ../infra-integration-setup/diskless_topics_names.txt