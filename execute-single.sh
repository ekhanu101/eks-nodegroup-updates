#!/bin/bash
#
# This script will attempt to execute change sets on specified eksctl node-groups for the given AWS profile.
# Requirements: awscli
#
#
set -euo pipefail

echo "enter the nodegroup that needs to be rolledback (ex. eksctl-rxcheck-cluster-nodegroup-ng-9e80b209)"
read s
echo "node group set to: $s"

# Pick aws profile - asp <profile>
echo "STEP 1.... check if aws profile set"
if [ -z "$AWS_PROFILE" ]
then
  echo "no AWS Profile set, please choose a profile and rerun script"
  exit
else
  echo "AWS Profile is set to $AWS_PROFILE\n"
fi

# Execute CFN Change Set
echo "...updating cfn stack"
execute=$(aws cloudformation execute-change-set --stack-name ${s} --change-set-name install-nodegroup-updates)
while :
do
    sleep 20
    status=$(aws cloudformation describe-stacks --stack-name ${s} | jq -r '.Stacks[0].StackStatus')
    echo "...update stack status...$status"
    if [ $status == "UPDATE_COMPLETE" ]
    then
        break
    fi
done

echo "...updating stack complete\n"