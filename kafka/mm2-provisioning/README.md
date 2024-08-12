# MM2 Provisioning
These scripts can be used as framework to help provision Kafka topics over multiple MM2 instances.

## by-througput
**This script relies on an external metrics source to evaluate throughput**
For cutoff:  If the highest throughput topic has a throughput of `10,000 mps`, and you set `high_throughput_threshold` to `80`, it means that any topic with a throughput of `8,000 mps` or higher would be considered *high-throughput*.

* The script iterates through the topics sorted by throughput in descending order.
* For each high-throughput topic, it checks which cluster has fewer partitions assigned and assigns the topic's partitions to that cluster.
* For other topics, it assigns partitions to the cluster that currently has the lower total throughput, effectively balancing the throughput load.
