# Autoscaling external ectd using Amazon EC2 auto scaling groups


## Tested EC2 Scenario:
1. Start with a working 0 etcd members in a vpc subnet using http protocol
2. Prepare custom AMI (see below) to be used in EC2 auto scaling group via a launch template to add members to cluster on demand

### Custom AMI Preprations:
1. amazon cmdline tool pre-installed
1. jq cmdline tool pre-installed
1. external etcd pre-installed and configured with tls if needed.
1. create `/var/lib/etcd-autoscale/` and directory owned by `etcd:etcd`
1. place `etcd-cluster-member-prepare.sh` into `/usr/local/bin/` and mark as executable by `etcd` user
1. make sure etcd service is stopped by enabled.
1. make sure the local etcd on disk data store is empty (default: `/var/lib/etcd-autoscale/etcd`)
1. add `etcd-autoscale.conf` at `/etc/systemd/system/etcd.service.d/etcd-autoscale.conf`
1. edit `/etc/systemd/system/etcd.d/etcd-autoscale.conf` as needed for you desired configuration
1. systemd daemon-reload to ensure systemd state is updated.
1. save EC2 image as a custom AMI to use in your autoscaling group launc template

### Autoscaling Launch Template Preparations:
1. make sure launch template is configured to set `etcd-cluster` tag with some value on all spawned instances
1. make sure autoscale instances launch using AIM role with `ec2.DescribeTags` and `ec2.DescribeInstances` access


## Operational details

### etcd-cluster-member-prepare.sh
This script will run before the main etcd service executable

### /etc/systemd/system/etcd.service.d/etcd-autoscale.conf
This is a systemd override file that extends the etcd service definition to run the `etcd-member-prepare.sh` script prior to starting the etcd service and to instruct systemd to read environment variables from the generated `/tmp/autoscale-etcd-cluster-env` file

### /tmp/autoscale-etcd-cluster-env 
This file is generated and holds environment variables represented etcd configuration overrides necessarily to construct the etcd cluster configuration dynamically from ec2 instance information.

### EC2 Instance tags
The autoscaling script relies on EC2 instance tags to discover which instances should be members of the etcd-cluster.
By default the tag name is `etcd-cluster`  and all EC2 instances in the same cluster should set this tag to the same value.

### AIM Role requirements
the script needs `ec2.DescribeTags` and `ec2.DescribeInstances`

### TODO
* Add support to select https etcd protocol from ec2 instance tag
