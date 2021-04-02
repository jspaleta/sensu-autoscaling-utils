#/bin/env bash

CLUSTER_TAG=${1:-sensu-cluster}
CLUSTER_NAME=${2:-test-cluster}
ETCD_PEER_PORT=2380
ETCD_CLIENT_PORT=2379
ETCD_PROTOCOL="http"

echo "ARGS: $#"
echo "CLUSTER_TAG: $CLUSTER_TAG"
echo "CLUSTER_NAME: $CLUSTER_NAME"

CURRENT_METADATA=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document)
CURRENT_REGION=$(echo $CURRENT_METADATA | jq .region | tr -d '"')
CURRENT_ID=$(echo $CURRENT_METADATA | jq .instanceId | tr -d '"')
CURRENT_PRIVATE_IP=$(echo $CURRENT_METADATA | jq .privateIp | tr -d '"')
CURRENT_SUBNET_ID=$(aws ec2 describe-instances --instance-id $CURRENT_ID --query 'Reservations[0].Instances[0].NetworkInterfaces[0].{"SubnetId":SubnetId}' --region $CURRENT_REGION --filter "Name=network-interface.addresses.private-ip-address,Values=10.0.0.151" | jq .SubnetId | tr -d '"')

CLUSTER_TAGS=$(aws ec2 describe-tags --filters "Name=resource-type,Values=instance" "Name=key,Values=$CLUSTER_TAG" "Name=value,Values=$CLUSTER_NAME" --region $CURRENT_REGION)

#CLUSTER_TAGS='{ "Tags": [ { "ResourceType": "instance", "ResourceId": "i-0ff5a44c33ef20523", "Value": "test-cluster", "Key": "sensu-cluster" } ] }'
#echo $CLUSTER_TAGS

CLUSTER_IDS=($(echo $CLUSTER_TAGS | jq .Tags[].ResourceId | tr -d '"'))
echo "Current\n" 
echo "  Id: $CURRENT_ID"
echo "  PrivateIP: $CURRENT_PRIVATE_IP"
echo "  SubnetId: $CURRENT_SUBNET_ID"


echo "Detecting if there is an active etcd cluster"
active_members=()
inactive_members=()
active_cluster_ids=()
for id in ${CLUSTER_IDS[@]}
do
	priv_ip=$(aws ec2 describe-instances --instance-id $id --filter --filter "Name=network-interface.subnet-id,Values=$CURRENT_SUBNET_ID" --query 'Reservations[0].Instances[0].NetworkInterfaces[0].{"PrivateIpAddress":PrivateIpAddress}' --region $CURRENT_REGION | jq .PrivateIpAddress | tr -d '"')
	running_endpoint="${ETCD_PROTOCOL}://${priv_ip}:${ETCD_CLIENT_PORT}/v2/stats/self"
	echo "Checking instance: $id using: $running_endpoint"
	running_json=$(curl -s -m 10 $running_endpoint)
	if [ $? -ne 0 ]; then
		echo "Cannot connect to instance $id at $running_endpoint"
		inactive_members+=($id)
		continue
	fi
	cluster_id=$(echo $running_json | jq .id)
	if [[ ! " ${active_cluster_ids[@]} " =~ " ${cluster_id} " ]]; then
		active_cluster_ids+=($cluster_id)
	fi
	active_members+=($id)
done

echo "Active Clusters Found: ${#active_cluster_ids[@]}"
if [ ${#active_cluster_ids[@]} -gt 1 ]; then 
    echo "Abort! More than 1 unique existing cluster found"  
fi 

echo "Active Cluster Members found: ${#active_members[@]}"
if [ ${#active_members[@]} -eq 0 ]; then 
    echo "No active cluster members"  
else 
    echo "There is an active cluster!"
fi

if [[ ! " ${CLUSTER_IDS[@]} " =~ " ${CURRENT_ID} " ]]; then
    echo "current id is not in cluster_ids"
fi



