# #!/bin/bash
# #
# #

echo $(date)
echo $(date +'%Y-%m-%d')
now=$(date +'%Y-%m-%d')
echo $now

export s="eksctl-methcheck-nodegroup-ng-e5c68c87"
keyid="!GetAtt KmsKey.KeyId"
echo $keyid

# echo "yq w -i $s-template-new.yaml 'Resources.NodeGroupLaunchTemplate.Properties.LaunchTemplateData.BlockDeviceMappings[0].Ebs.KmsKeyId' --style=flow $keyid"
yq w -i $s-template-new.yaml 'Resources.NodeGroupLaunchTemplate.Properties.LaunchTemplateData.BlockDeviceMappings[0].Ebs.KmsKeyId' REPLACEKEYID


 cat $s-template-new.yaml | sed "s/REPLACEKEYID/$keyid/g" >> $s-template-new.yaml
