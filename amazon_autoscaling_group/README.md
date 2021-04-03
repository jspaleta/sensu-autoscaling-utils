# On-boot actions to take when adding a new cluster member into a Sensu cluster using Amazon EC2 instances

## AMI Prereqs:
1. amazon cmdline tool pre-installed
1. jq cmdline tool pre-installed
1. sensu-backend pre-installed, using systemd based service init
1. create `/var/lib/sensu/sensu-backend-autoscale/` and `/var/cache/sensu/sensu-backend-autoscale/` directories owned by `sensu:sensu`
1. place `sensu-cluster-member-prepare.sh` into `/usr/local/bin/` and mark as executable by `sensu` user
1. make sure sensu-backend service is stopped by enabled.
1. make sure the local etcd on disk data store is empty (default: `/var/lib/sensu/sensu-backend-autoscale/etcd`)
1. add `sensu-backend-autoscale.conf` at `/etc/systemd/system/sensu-backend.service.d/sensu-backend-autoscale.conf`
1. edit `/etc/systemd/system/sensu-backend.service.d/sensu-backend-autoscale.conf` as needed for you desired configuration
1. systemd daemon-reload to ensure systemd state is updated.
1. save EC2 image as a custom AMI to use in your autoscaling group launc template
1. make sure autoscale launch template is configured to set `sensu-cluster` tag with some value on all spawned instances
1. make sure autoscale instances launch using AIM role with `ec2.DescribeTags` and `ec2.DescribeInstances` access


### EC2 Instance tags
The autoscaling script relies on EC2 instance tags to discover which instances should be members of the sensu-cluster.
By default the tag name is `sensu-cluster`  and all EC2 instances in the same cluster should set this tag to the same value.

### AIM Role requirements
the script needs `ec2.DescribeTags` and `ec2.DescribeInstances`
