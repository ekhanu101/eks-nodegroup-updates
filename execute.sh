#!/bin/bash
#
## SCRIPT MUST BE RUN IN EACH AWS ACCOUNT
#
# This script will attempt to execute change sets named 'install-nodegroup-updates' on all eksctl node-groups for the given AWS profile.
# Requirements: awscli, asp, jq
#
#
set -euo pipefail

#1 Pick aws profile - asp <profile>
echo "STEP 1.... check if aws profile set"
if [ -z "$AWS_PROFILE" ]
then
  echo "no AWS Profile set, please choose a profile and rerun script"
  exit
else
  echo "AWS Profile is set to $AWS_PROFILE\n"
fi

#2 Get list of node group stacks that have active launch templates and add to array variable
echo "STEP 2... get list of node group stacks"
stacks=$(aws cloudformation list-stacks | jq -r '.StackSummaries[] | select(.StackName | contains("nodegroup")) | select(.StackStatus | contains("DELETE") | not) | .StackName')
printf '%s\n' "${stacks[@]}"
echo "...complete\n"

#3 Execute CFN Change Set
echo "STEP 4... update each node group"
for s in $stacks
do
  echo "EXECUTING ${s}"
  
  # check if change set exists, if not, move on
  changeset=$(aws cloudformation list-change-sets --stack-name ${s} | jq -r '.Summaries[] | select(.ChangeSetName | startswith("install-nodegroup-updates")) | .ChangeSetName')
  if [ -z $changeset ]
  then
    echo "no change set to apply, moving on...."
  else
    echo "executing $changeset"
    execute=$(aws cloudformation execute-change-set --stack-name ${s} --change-set-name install-nodegroup-updates)
  fi
done
echo "...updating stacks complete\n"