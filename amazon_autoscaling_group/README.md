# Autoscaling cluster member into a Sensu cluster using Amazon EC2 auto scaling groups


## Tested EC2 Scenario:
1. Start with a working 3 member sensu-cluster in a vpc subnet using http protocol (as documented in the Sensu Go clustering guide)
2. Prepare custom AMI (see below) to be used in EC2 auto scaling group via a launch template to add members to cluster on demand

### Custom AMI Preprations:
1. amazon cmdline tool pre-installed
1. jq cmdline tool pre-installed
1. sensu-backend pre-installed and configured with tls if needed.
1. create `/var/lib/sensu/sensu-backend-autoscale/` and `/var/cache/sensu/sensu-backend-autoscale/` directories owned by `sensu:sensu`
1. place `sensu-cluster-member-prepare.sh` into `/usr/local/bin/` and mark as executable by `sensu` user
1. make sure sensu-backend service is stopped by enabled.
1. make sure the local etcd on disk data store is empty (default: `/var/lib/sensu/sensu-backend-autoscale/etcd`)
1. add `sensu-backend-autoscale.conf` at `/etc/systemd/system/sensu-backend.service.d/sensu-backend-autoscale.conf`
1. edit `/etc/systemd/system/sensu-backend.service.d/sensu-backend-autoscale.conf` as needed for you desired configuration
1. systemd daemon-reload to ensure systemd state is updated.
1. save EC2 image as a custom AMI to use in your autoscaling group launc template

### Autoscaling Launch Template Preparations:
1. make sure launch template is configured to set `sensu-cluster` tag with some value on all spawned instances
1. make sure autoscale instances launch using AIM role with `ec2.DescribeTags` and `ec2.DescribeInstances` access


## Operational details

### sensu-cluster-member-prepare.sh
This script will run before the main sensu-backend 

### /etc/systemd/system/sensu-backend.service.d/sensu-backend-autoscale.conf
This is a systemd override file that extends the sensu-backend service definition to run the `sensu-cluster-member-prepare.sh` script prior to starting the sensu-backend service and to instruct systemd to read environment variables from the generated `/tmp/autoscale-sensu-cluster-env` file

### /tmp/autoscale-sensu-cluster-env 
This file is generated and holds environment variables represented sensu-backend configuration overrides necessarily to construct the etcd cluster configuration dynamically from ec2 instance information.

### EC2 Instance tags
The autoscaling script relies on EC2 instance tags to discover which instances should be members of the sensu-cluster.
By default the tag name is `sensu-cluster`  and all EC2 instances in the same cluster should set this tag to the same value.

### AIM Role requirements
the script needs `ec2.DescribeTags` and `ec2.DescribeInstances`

### TODO
* Add support to select https etcd protocol from ec2 instance tag
