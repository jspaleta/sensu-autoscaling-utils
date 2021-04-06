while IFS= read -r dest; do
  scp sensu-cluster-member-prepare.sh "$dest:/home/centos/"
  scp test.sh "$dest:/home/centos/"
  scp test.service "$dest:/home/centos/"
  scp sensu-backend-autoscale.conf "$dest:/home/centos/"
done <destfile.txt

