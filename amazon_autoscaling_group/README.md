# On-boot actions to take when adding a new cluster member into a Sensu cluster using Amazon EC2 instances

## Prereqs:
1. amazon cmdline tool pre-installed
1. sensu-backend pre-installed, using systemd based service init
1. ec2 instance using AIM role with ec2.DescribeTags access

## EC2 instance preparations
1. place `sensu-cluster-member-prepare.sh` into `/usr/local/bin/`
1. make sure sensu-backend service is stopped by enabled.
1. make sure the local etcd on disk data store is empty (default: `/var/lib/sensu/sensu-backend/etcd`)
1. make sure sensu-backend config file does not set any of the etcd cluster settings. These will be set using the autoscaling script using environment variables injected into the sensu-backend running environment.
1. run `sensu-cluster-member-prepare.sh` as sensu user  to verify everything is ready.
1. add `sensu-backend-autoscale.conf` at `/etc/systemd/system/sensu-backend.service.d/sensu-backend-autoscale.conf`
1. edit `/etc/systemd/system/sensu-backend.service.d/sensu-backend-autoscale.conf` as needed for you desired configuration
1. systemd daemon-reload to ensure systemd state is updated.
1. save EC2 image as a custom AMI to use in your autoscaling group
1. ensure necessary AWS EC2 tags exist for autoscaling group (see tags section below)

## Config

### EC2 Instance tags
The autoscaling script relies on EC2 instance tags to figure out cluster configuration details

### Script Options


### AIM Role requirements

