# SONM ScyllaDB Manager
SONM is a powerful distributed worldwide system for general-purpose computing, implemented as a fog computing structure.
Consumers of computing power in SONM get more cost-efficient solutions than cloud services., more information you can get at [docs.sonm.com](https://docs.sonm.com) and [sonm.com](https://sonm.com).

[ScyllaDB](https://www.scylladb.com/open-source/) is the next generation of NoSQL, based on Apache Cassandra design. Scylla Open Source leverages Apache Cassandra’s innovation and track record, but takes it to the next level. Implemented in C++14 from scratch, Scylla has a shared-nothing, thread-per-core design. [More information](http://docs.scylladb.com/)

This script manages to run ScyllaDB distributed on SONM suppliers.


## Getting started
First of all you need to install sonmnode and sonmcli, you can do this by following [this guide](https://docs.sonm.io/getting-started/as-a-consumer)

### Prerequisites
Works only on Linux and MacOS, BSD systems not tested but may work.

Make sure you have installed all of the following prerequisites on your machine:
* sonmcli
* sonmnode
* jq
* xxd
* wget
* cqlsh (pip install cqlsh)



### Installing
```
git clone https://github.com/akme/sonm-scylla
```

## Deployment
To better understand node requirements please read [system requirements](http://docs.scylladb.com/operating-scylla/admin/#system-requirements)
Before deployment you need to set parameters of cluster in config.sh
* tag - cluster name used to mark BIDs and tasks
* numberofnodes - cluster size 
* ramsize - RAM size in GB that each node will have
* storagesize - storage size in GB that each node will have
* cpucores - number of CPU cores that each node will have
* sysbenchsingle - minimal CPU performance for 1 CPU core
* sysbenchmulti - minimal CPU performance for multi core systems (multithreading)
* netdownload - minimal download speed in Mbits for a deal
* netupload - minimal upload speed in Mbits for a deal
* price - price in USD for deal per hour

When all parameters are set, run:
```
./nosql.sh watch
```
This will create number of orders equal to numberofnodes you've set, when any order will become a deal, script will start task on it, each next task (next deal) will join cluster created by previous tasks.

When all orders created, all deals are set and have tasks running, it will watch for deals, if deal drops then it creates new orders, wait for deal and start task on it.

Currently SONM doesn't let you filter deals based on some parameters that are essential for ScyllaDB to operate. So you can find that some tasks don't appear in cluster, the case could be that they don't support SSE 4.2 CPU instructions. You can just close such deals and find another supplier that support it.

### Example of output
```
$ ./nosql.sh watch 
./nosql.sh watch                                                                              
2018-08-20 19:43:33 Creating 7 order(s)
ID = 166955
ID = 166956
ID = 166960
ID = 166964
ID = 166967
ID = 166968
ID = 166969
2018-08-20 19:47:05 All set, waiting for deals
2018-08-20 19:47:05 watching cluster
2018-08-20 19:47:40 Starting task on deal 4608 with
Task ID:    3de317b8-491b-4d2c-a5db-13419faff1e6
  Endpoint: 10000/tcp: 85.119.150.185:10000
  Endpoint: 10000/tcp: 172.17.0.1:10000
  Endpoint: 7000/tcp: 85.119.150.185:7000
  Endpoint: 7000/tcp: 172.17.0.1:7000
  Endpoint: 7001/tcp: 85.119.150.185:7001
  Endpoint: 7001/tcp: 172.17.0.1:7001
  Endpoint: 9042/tcp: 85.119.150.185:9042
  Endpoint: 9042/tcp: 172.17.0.1:9042
  Endpoint: 9160/tcp: 85.119.150.185:9160
  Endpoint: 9160/tcp: 172.17.0.1:9160
  Endpoint: 9180/tcp: 85.119.150.185:9180
  Endpoint: 9180/tcp: 172.17.0.1:9180
  Network:  sonmbcfa4942
2018-08-20 19:48:01 Starting task on deal 4609 with --seeds 85.119.150.185
Task ID:    adc7870a-cc83-4fa1-a42a-dc2b164e5a27
  Endpoint: 9180/tcp: 185.144.156.200:9180
  Endpoint: 9180/tcp: 172.17.0.1:9180
  Endpoint: 10000/tcp: 185.144.156.200:10000
  Endpoint: 10000/tcp: 172.17.0.1:10000
  Endpoint: 7000/tcp: 185.144.156.200:7000
  Endpoint: 7000/tcp: 172.17.0.1:7000
  Endpoint: 7001/tcp: 185.144.156.200:7001
  Endpoint: 7001/tcp: 172.17.0.1:7001
  Endpoint: 9042/tcp: 185.144.156.200:9042
  Endpoint: 9042/tcp: 172.17.0.1:9042
  Endpoint: 9160/tcp: 185.144.156.200:9160
  Endpoint: 9160/tcp: 172.17.0.1:9160
  Network:  sonm5f5e3004
  ...
  ...
  etc...
```
## How to use
After starting a task you will get an IP and port to access.

To get into CQLSH you can run:
```
export CQLSH_HOST="<any node ip>"
cqlsh
```
To get familiar with CQLSH you can read about [CQL](http://docs.scylladb.com/getting-started/cql/).

### Create user
Currently it's not able to create users and runs only in unauthenicated mode for tests only.

### Get cluster IP
You can get all cluster nodes IP addresses:
```
./nosql.sh getips
```

### Replication factor
By default ScyllaDB only forms a cluster and replication factor is set for each keyspace independent.
```
cqlsh> CREATE KEYSPACE Sonm
WITH replication = {'class': 'SimpleStrategy', 'replication_factor' : 3};
```
To change replication factor for existing keyspace:
```
cqlsh> ALTER KEYSPACE Excelsior
          WITH replication = {'class': 'SimpleStrategy', 'replication_factor' : 4};
```
Cluster need some time to make additional copies of data, so be patient to wait until sync ends.
### Destroy cluster
When you want to stop using and destroy cluster, you just need to close all deals and cancel orders:
```
./nosql.sh cancelorders
./nosql.sh closedeals
```
It will stop all tasks and cleanup all created deals and orders.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details
