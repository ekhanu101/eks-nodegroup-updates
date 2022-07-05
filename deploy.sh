#!/bin/bash
#
# SCRIPT MUST BE RUN IN EACH AWS ACCOUNT
#
# This script will create CFN change sets for all eksctl node-groups to perform:
# ((add to list as more things are added))
# nessus agent install
# crowdstrike install
# create & encrypt boot volumes
# create kms key, alias, policy
# security updates
#
#
# Requirements: awscli, asp, jq, yq
#
#
set -euo pipefail

# ------------------------------------------------------------------
# VARIABLES & PREWORK
# ------------------------------------------------------------------

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

# Get list of node group stacks that have active launch templates and add to array variable
echo "STEP 3... get list of node group stacks"
stacks=$(aws autoscaling describe-auto-scaling-groups | jq -r '.AutoScalingGroups[] | select(.AutoScalingGroupName | startswith("eksctl")) | select(.LaunchTemplate.LaunchTemplateName != null) | .LaunchTemplate.LaunchTemplateName')
printf '%s\n' "${stacks[@]}"
echo "...complete\n"

# ------------------------------------------------------------------
# PULL TEMPLATES
# ------------------------------------------------------------------
echo "STEP 4... update each node group"
for s in $stacks
do
  echo "UPDATING ${s}"

  # Get template body and save to text file
  echo "...getting template body"
  aws cloudformation get-template --stack-name ${s} | jq -r '.TemplateBody' > ${s}-template-old.yaml

  # Extract userdata from template and save to file
  echo "...extracting userdata"
  aws ec2 describe-launch-templates --launch-template-name ${s} | jq -r '.LaunchTemplates[0].LaunchTemplateId' | xargs -I {} -- aws ec2 describe-launch-template-versions --launch-template-id {} | jq -r '.LaunchTemplateVersions[0].LaunchTemplateData.UserData' | base64 -d | zcat > ${s}-userdata.txt

# ------------------------------------------------------------------
# MODIFY USER DATA
# ------------------------------------------------------------------

  # Add install commands to userdata file and save
  echo "...updating userdata"
  yq w ${s}-userdata.txt 'runcmd' '' > ${s}-userdata-new.txt
  # perform security patching
  yq w -i ${s}-userdata-new.txt 'runcmd[+]' "sudo yum update -y --security"
  # install nessus agent
  yq w -i ${s}-userdata-new.txt 'runcmd[+]' "sudo yum install -y https://s3.amazonaws.com/security-downloads.infosec.corporate.s3.appriss.com/664ae2fd-dc09-4ce0-87b9-995490e9a348/NessusAgent-amzn.x86_64.rpm"
  yq w -i ${s}-userdata-new.txt 'runcmd[+]' 'sudo systemctl enable nessusagent'
  yq w -i ${s}-userdata-new.txt 'runcmd[+]' 'sudo systemctl start nessusagent'
  yq w -i ${s}-userdata-new.txt 'runcmd[+]' 'sudo /opt/nessus_agent/sbin/nessuscli agent link --key=66f89a2aa3113a80174d65d74cf1a891b429e1c52faeb086d54d2cf3e305fb80 --groups='${account_alias}'_aws  --host=cloud.tenable.com --port=443'
  # install crowdstrike
  yq w -i ${s}-userdata-new.txt 'runcmd[+]' 'sudo yum install -y https://s3.amazonaws.com/security-downloads.infosec.corporate.s3.appriss.com/664ae2fd-dc09-4ce0-87b9-995490e9a348/appriss-cs-falcon-sensor.amzn2.x86_64.rpm'
  yq w -i ${s}-userdata-new.txt 'runcmd[+]' 'sudo /opt/CrowdStrike/falconctl -s --cid=8A9ADAFAAAE848798D13279632AC2EE3-69'
  yq w -i ${s}-userdata-new.txt 'runcmd[+]' 'sudo systemctl enable --now falcon-sensor'
  yq w -i ${s}-userdata-new.txt 'runcmd[+]' '/var/lib/cloud/scripts/per-instance/bootstrap.al2.sh'
  yq w -i ${s}-userdata-new.txt 'package_update' 'true'
  yq w -i ${s}-userdata-new.txt 'package_upgrade' 'true'
  yq w -i ${s}-userdata-new.txt 'package_reboot_if_required' 'true'
  yq d -i ${s}-userdata-new.txt 'preBootstrapCommands'

  # Encode/compress userdata file and save output to variable
  echo "...encoding userdata"
  new_userdata=$(cat ${s}-userdata-new.txt | gzip -c | base64)

  # Replace userdata in template file with new userdata and save
  echo "...replacing userdata in template"
  yq w ${s}-template-old.yaml 'Resources.NodeGroupLaunchTemplate.Properties.LaunchTemplateData.UserData' $new_userdata > ${s}-template-new.yaml

# ------------------------------------------------------------------
#  MODIFY LAUNCH TEMPLATE
# ------------------------------------------------------------------

  # Set boot volumes to KMS encrypted
  echo "...modifying launch template"

  # Get NodeGroup Role ARN
  export ng=${s}
  role=$(aws cloudformation list-exports | jq -r '.Exports[] | select(.Name | startswith(env.ng)) | select(.Name | contains("InstanceRoleARN")) | .Value')
  echo "nodegroup role arn: $role"

  # Create KMS Key and Alias
  yq w -i -s kms-create.yaml ${s}-template-new.yaml
  yq w -i ${s}-template-new.yaml 'Resources.KmsKey.Properties.KeyPolicy.Statement[1].Principal.AWS' $role

  # Get KMS Key ID to be used for eks volume encryption
  # keyid=$(aws kms list-aliases | jq -r '.Aliases[] | select(.AliasName | contains("eks-encryption-key")) | .TargetKeyId')
  # echo "kms key used for encryption: $keyid"

keyid="!Ref KmsKey"

  blockdevice=$(yq r ${s}-template-new.yaml --length 'Resources.NodeGroupLaunchTemplate.Properties.LaunchTemplateData.BlockDeviceMappings')
  if [ -z $blockdevice ]
  then
    echo "need to add block device"
    yq w -i ${s}-template-new.yaml 'Resources.NodeGroupLaunchTemplate.Properties.LaunchTemplateData.BlockDeviceMappings[+].DeviceName' '/dev/xvda'
    yq w -i ${s}-template-new.yaml 'Resources.NodeGroupLaunchTemplate.Properties.LaunchTemplateData.BlockDeviceMappings[0].Ebs.Encrypted' true
    yq w -i ${s}-template-new.yaml 'Resources.NodeGroupLaunchTemplate.Properties.LaunchTemplateData.BlockDeviceMappings[0].Ebs.VolumeSize' 64
    yq w -i ${s}-template-new.yaml 'Resources.NodeGroupLaunchTemplate.Properties.LaunchTemplateData.BlockDeviceMappings[0].Ebs.VolumeType' gp2
    yq w -i ${s}-template-new.yaml 'Resources.NodeGroupLaunchTemplate.Properties.LaunchTemplateData.BlockDeviceMappings[0].Ebs.KmsKeyId' REPLACEKEYID
  elif [ $blockdevice -gt 0 ]
  then
    echo "...encrypting boot volumes"
    yq w -i ${s}-template-new.yaml 'Resources.NodeGroupLaunchTemplate.Properties.LaunchTemplateData.BlockDeviceMappings.*.Ebs.Encrypted' true
    yq w -i ${s}-template-new.yaml 'Resources.NodeGroupLaunchTemplate.Properties.LaunchTemplateData.BlockDeviceMappings.*.Ebs.KmsKeyId' REPLACEKEYID
  # Upsize boot volume if needed
    currentsize=$(yq r ${s}-template-new.yaml 'Resources.NodeGroupLaunchTemplate.Properties.LaunchTemplateData.BlockDeviceMappings.*.Ebs.VolumeSize')
    if [ $currentsize -lt 63 ]
    then
      echo "...upsizing boot volumes"
      yq w -i ${s}-template-new.yaml 'Resources.NodeGroupLaunchTemplate.Properties.LaunchTemplateData.BlockDeviceMappings.*.Ebs.VolumeSize' 64
    fi
  fi

  # Add KMS Key to Launch Template
  keyid="!Ref KmsKey"
  cat $s-template-new.yaml | sed "s/REPLACEKEYID/$keyid/g" >> temp-template.yaml
  cp -f temp-template.yaml $s-template-new.yaml
  rm -f temp-template.yaml



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
