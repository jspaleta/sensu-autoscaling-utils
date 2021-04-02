#!/bin/env bash

###
#  Utility script to help auto-scale Sensu with embedded etcd when used with EC2 auto scaling groups
#  Pre-reqs:
#    EC2 instances must be using an AIM role that allows for read access to ec2 describe-tags and describe-instances
#    Auto scaling group must use EC2 image pre-configured with Sensu backend service pre-configured in stand-alone configuration.
#    All EC2 instances to be made part of the cluster must be in the same EC2 subnet definition
#    ALL EC2 instances must include tag with cluster-name
### 

CLUSTER_TAG=${1:-sensu-cluster}
CLUSTER_NAME=${2:-test-cluster}
if [ -n "$3" ]; then
  ENABLE_CLEANUP="true"
fi
ETCD_PEER_PORT=2380
ETCD_CLIENT_PORT=2379
ETCD_PROTOCOL="http"
ENV_FILE="/tmp/autoscale-sensu-cluster-env"

DATA_DIR="/var/lib/sensu/sensu-backend-autoscale"
CACHE_DIR="/var/cache/sensu/sensu-backend-autoscale"
SENSU_USER="sensu"
SENSU_GROUP="sensu"

echo "ARGS: $#"
echo "CLUSTER_TAG: $CLUSTER_TAG"
echo "CLUSTER_NAME: $CLUSTER_NAME"

##
# Get metadata for this EC2 instance
##
CURRENT_METADATA=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document)
CURRENT_REGION=$(echo $CURRENT_METADATA | jq .region | tr -d '"')
CURRENT_ID=$(echo $CURRENT_METADATA | jq .instanceId | tr -d '"')
CURRENT_PRIVATE_IP=$(echo $CURRENT_METADATA | jq .privateIp | tr -d '"')
CURRENT_SUBNET_ID=$(aws ec2 describe-instances --instance-id $CURRENT_ID --query 'Reservations[0].Instances[0].NetworkInterfaces[0].{"SubnetId":SubnetId}' --region $CURRENT_REGION --filter "Name=network-interface.addresses.private-ip-address,Values=10.0.0.151" | jq .SubnetId | tr -d '"')

echo "Current\n" 
echo "  Id: $CURRENT_ID"
echo "  PrivateIP: $CURRENT_PRIVATE_IP"
echo "  SubnetId: $CURRENT_SUBNET_ID"

##
# Get all EC2 instances that are tagged as part of the cluster
##
CLUSTER_TAGS=$(aws ec2 describe-tags --filters "Name=resource-type,Values=instance" "Name=key,Values=$CLUSTER_TAG" "Name=value,Values=$CLUSTER_NAME" --region $CURRENT_REGION)
CLUSTER_IDS=($(echo $CLUSTER_TAGS | jq .Tags[].ResourceId | tr -d '"'))

# Remove old autoscale env file if it exists
rm $ENV_FILE 

# The current system needs to be part of cluster
if [[ ! " ${CLUSTER_IDS[@]} " =~ " ${CURRENT_ID} " ]]; then
    echo "Abort! current id is not in cluster_ids"
    exit 2
fi

echo "Detecting if there is an active etcd cluster present on any ec2 instance matching cluster tags"
active_members=()
inactive_members=()
active_etcd_cluster_ids=()
for id in ${CLUSTER_IDS[@]}
do
	priv_ip=$(aws ec2 describe-instances --instance-id $id --filter --filter "Name=network-interface.subnet-id,Values=$CURRENT_SUBNET_ID" --query 'Reservations[0].Instances[0].NetworkInterfaces[0].{"PrivateIpAddress":PrivateIpAddress}' --region $CURRENT_REGION | jq .PrivateIpAddress | tr -d '"')
        if [ -z "$priv_ip" ]; then
		echo "Instance: $id not in subnet: $CURRENT_SUBNET_ID"
		continue
	fi
	running_endpoint="${ETCD_PROTOCOL}://${priv_ip}:${ETCD_CLIENT_PORT}/v2/stats/self"
	echo "Checking instance: $id using: $running_endpoint"
	running_json=$(curl -s -m 10 $running_endpoint)
	if [ $? -ne 0 ]; then
		echo "Cannot connect to instance $id at $running_endpoint"
		inactive_members+=($id)
		continue
	fi
	cluster_id=$(echo $running_json | jq .id)
	if [[ ! " ${active_etcd_cluster_ids[@]} " =~ " ${cluster_id} " ]]; then
		active_etcd_cluster_ids+=($cluster_id)
	fi
	echo "EC2 instance: $id running etcd cluster: $cluster_id"
	active_members+=($id)
done

echo "Active etcd clusters Found: ${#active_etcd_cluster_ids[@]}"
if [ ${#active_ectd_cluster_ids[@]} -gt 1 ]; then 
    echo "Abort! More than 1 existing etcd cluster found. Cannot safely auto-scale!"
    exit 2  
fi 
if [ ${#active_etcd_cluster_ids[@]} -eq 0 ]; then 
    echo "Abort! No existing ietcd clusters found. Cannot safely auto-scale!"
    exit 2  
fi 

# This system must not be running an etcd node already
if [[ " ${active_members[@]} " =~ " ${CURRENT_ID} " ]]; then
    echo "Abort! current ec2 instance is already running an an etcd cluster node."
    exit 2
fi


# There must be an existing etcd cluster to scale up
echo "Active ectd Cluster Members found: ${#active_members[@]}"
if [ ${#active_members[@]} -eq 0 ]; then 
    echo "Abort! No active cluster members. This is a new cluster. Cannot safely auto-scale"
    exit 2  
fi

etcd_cluster_ip=$(aws ec2 describe-instances --instance-id ${active_members[0]} --filter --filter "Name=network-interface.subnet-id,Values=$CURRENT_SUBNET_ID" --query 'Reservations[0].Instances[0].NetworkInterfaces[0].{"PrivateIpAddress":PrivateIpAddress}' --region $CURRENT_REGION | jq .PrivateIpAddress | tr -d '"')

echo "Using EC2 instance: ${active_members[0]} for etcd cluster communication: $etcd_cluster_ip"


# Get etcd members
members_endpoint="${ETCD_PROTOCOL}://${etcd_cluster_ip}:${ETCD_CLIENT_PORT}/v2/members"
echo "Getting etcd members using: $members_endpoint"
members_json=$(curl -s -m 10 $members_endpoint)
etcd_members=($(echo $members_json | jq -c .members[] ))

# Clean up inactive etcd members
active_members=()
inactive_members=()
for member in ${etcd_members[@]}
do
	url=$( echo $member | jq .clientURLs[0] | tr -d '"')
	running_endpoint="$url/v2/stats/self"
	echo "Checking instance: $url using: $running_endpoint"
	running_json=$(curl -s -m 10 $running_endpoint)
	if [ $? -ne 0 ]; then
		echo "Cannot connect to instance $url at $running_endpoint"
		inactive_members+=($member)
		continue
	fi
	active_members+=($member)
done

for member in ${inactive_members[@]}
do
	echo "Deleting inactive etcd member: $member"
	id=$(echo $member | jq .id | tr -d '"')
	curl_command="curl -s http://10.0.0.10:2379/v2/members/$id -XDELETE"
	if [ -n "$ENABLE_CLEANUP" ]; then
		echo "cleaning up with $curl_command"
        else
		echo -e "automatic cleanup not enabled for inactive etcd member: $id\n  remove manually with: curl -s http://10.0.0.10:2379/v2/members/$id -XDELETE"
	fi
done

# Prepare Cache and Data directories 
mkdir -p $CACHE_DIR
mkdir -p $DATA_DIR
chown $SENSU_USER:$SENSU_GROUP $CACHE_DIR
chown $SENSU_USER:$SENSU_GROUP $DATA_DIR
chmod o-rwx $CACHE_DIR
chmod o-rwx $DATA_DIR

# Abort if etcd directory exists
if [ -d "${DATA_DIR}/etcd" ]; then
	echo "Abort! Directory ${DATA_DIR}/etcd already exists. Unsafe to autoscale"
	exit 2
fi

# Build Variables
echo "Setting Sensu variables in ${ENV_FILE}"

TEST_MSG="i test you test we all test"

cat << EOF > ${ENV_FILE}
# File used by Sensu autoscaling script
# 

TEST_MSG="${TEST_MSG}"

EOF


