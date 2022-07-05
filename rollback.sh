#!/bin/bash
#
# This script will attempt to install prior dpeloyments on specified eksctl node-groups for the given AWS profile.
# Requirements: awscli, asp, jq
#
#
set -euo pipefail

AWS_PROFILE=$1
s=$2
echo "AWS Profile set to: $AWS_PROFILE"
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

# Assign aws account alias to variable `account_alias`
echo "STEP 2... get aws account alias"
eval account_alias=`aws iam list-account-aliases | jq -r '.AccountAliases[0]'`
echo "account alias assigned as: $account_alias"
echo "...complete\n"

# Create CFN Change Set using new template
echo "...creating change set"
echo "file://${account_alias}-files/${s}-template-old.yaml"
change_set=$(aws cloudformation create-change-set --stack-name ${s} --change-set-name rollback-nodegroup-updates --change-set-type UPDATE --capabilities CAPABILITY_IAM --template-body file://${account_alias}-files/${s}-template-old.yaml)
while :
do
 status=$(aws cloudformation describe-change-set --stack-name ${s} --change-set-name rollback-nodegroup-updates | jq -r '.ExecutionStatus')
 echo "...create change set status...$status"
 if [ $status == "AVAILABLE" ]
 then
   break
 fi
done

# Execute CFN Change Set
echo "...updating cfn stack"
execute=$(aws cloudformation execute-change-set --stack-name ${s} --change-set-name rollback-nodegroup-updates)
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

echo "UPDATING ${s} COMPLETED in $SECONDS\n\n"