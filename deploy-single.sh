#!/bin/bash
#
# SCRIPT MUST BE RUN IN EACH AWS ACCOUNT
#
# This script will create CFN change sets for all eksctl node-groups to perform:
# ((add to list as more things are added))
#
#ASSUMES FOLLOWiNG CHANGES ALREADY EXIST:
# nessus agent install
# crowdstrike install
# create & encrypt boot volumes
# create kms key, alias, policy
# security updates
#
# CHANGE TO BE ADDED:
# max instance lifetime
#
#
# Requirements: awscli, asp, jq, yq
#
#
set -euo pipefail

# ------------------------------------------------------------------
# VARIABLES & PREWORK
# ------------------------------------------------------------------

AWS_PROFILE=$1
s=$2

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

# SET S EQUAL TO STACKNAME
# s="eksctl-bi-cluster-nodegroup-ng-ac8dfa29"

# ------------------------------------------------------------------
# PULL TEMPLATES
# ------------------------------------------------------------------
echo "STEP 4... update each node group"
  echo "UPDATING ${s}"

  # Get template body and save to text file
  echo "...getting template body"
  aws cloudformation get-template --stack-name ${s} | jq -r '.TemplateBody' > ${s}-template-old.yaml

  # Extract userdata from template and save to file
  # not needed for this version

# ------------------------------------------------------------------
# MODIFY USER DATA
# ------------------------------------------------------------------

  # not needed for this version

# ------------------------------------------------------------------
#  MODIFY LAUNCH TEMPLATE
# ------------------------------------------------------------------

  echo "...modifying launch template"

  # Create KMS Key and Alias
  cp -f ${s}-template-old.yaml ${s}-template-new.yaml

  # Add MaxInstanceLifetime to Node Group
  yq w -i ${s}-template-new.yaml 'Resources.NodeGroup.Properties.MaxInstanceLifetime' 1209600

# ------------------------------------------------------------------
#  CREATE CFN CHANGE SET
# ------------------------------------------------------------------
  # Create CFN Change Set using new template
  echo "...creating change set"
  change_set=$(aws cloudformation create-change-set --stack-name ${s} --change-set-name install-nodegroup-updates --change-set-type UPDATE --capabilities CAPABILITY_IAM --template-body file://${s}-template-new.yaml | jq -r '.Id')
  echo "change set: ${change_set}"
  while :
  do
    status=$(aws cloudformation describe-change-set --stack-name ${s} --change-set-name install-nodegroup-updates | jq -r '.ExecutionStatus')
    echo "...create change set status...$status"
    if [ $status == "AVAILABLE" ]
    then
      echo "...complete\n"
      break
    fi
  done

echo "...updating stacks complete\n"

# ------------------------------------------------------------------
#  BACKUP FILES
# ------------------------------------------------------------------
# Move files to account folder
echo "STEP 6... moving files"
mkdir -p ${account_alias}-files
mv eksctl* ${account_alias}-files
echo "...complete\n"

echo "ALL stacks updated.... VALIDATE there are no issues!\rShould an issue occur, you can redeploy the old template."
echo "All created files have been moved to a folder named ${account_alias}-files"
exit
