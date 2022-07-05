# Scripted EKS Automation Deployments

These scripts are currently set to automatically install various updates to instances on an EKS node group. They can be modified for other automation purposes.

## Current Updates Included

* Nessus agent install
* Crowdstrike install
* Create & encrypt boot volumes
* Create KMS key, alias, policy
* Security updates
* Max instance lifetime

## Components

* `deploy.sh`
* `deploy-single.sh`
* `execute.sh`
* `execute-single.sh`
* `rollback.sh`
* `rollback-patching.sh`
* `test.sh`
* `kms-create.yaml`

___

## Requirements

* `awscli`
* `asp`
* `jq`
* `yq` (version < 4)
* `sed`

___

## Deploy

This script will create a stack change set to install various updates on all `eksctl` node-groups that have an ASG actively using a Launch Template for the given AWS profile. The old/new stack templates and userdata are saved in files and then moved to a folder named after the stack. The old template can be used to rollback changes.

Requires: `awscli`, `asp`, `jq`, `yq`

Change set that will be created: "`install-nodegroup-updates`"
___

## Deploy-Single

This script functions the same as Deploy, however you must explicitly specify a stackname in the script so that it will only perform updates to that stack.

execute via command: `sh deploy-single.sh AWSPROFILE STACKNAME`

example:

```bash
sh deploy-single.sh hp-sharedservices-infrastructure eksctl-vault-nodegroup-ng-4807e83c
```

Requires: `awscli`, `asp`, `jq`, `yq`

Change set that will be created: "`install-nodegroup-updates`"
___

## Execute

This script will attempt to execute change sets named "`install-nodegroup-updates`" on all node-group stacks for the given AWS profile.

The script will cycle through each stack containing "nodegroup" in its name and check if a change set "install-nodegroup-updates" exists. If the change set is present, it will be executed, otherwise the script will move on to the next stack.

This script does not keep track of change set status, so there is nothing preventing each change set from being executed. You will need to monitor progress in the AWS console or run separate awscli commands.

Requirements: `awscli`, `jq`
___

## Execute-Single

This script will attempt to execute "`install-nodegroup-updates`" change set on a specified `eksctl` node-group for the given AWS profile. This script can be used for stacks that do not have ASGs using Launch Templates.

Requirements: `awscli`
___

execute via command: `sh rollback.sh AWSPROFILE STACKNAME`

example:

```bash
sh rollback.sh hp-sharedservices-infrastructure eksctl-vault-nodegroup-ng-4807e83c
```

Requirements: `awscli`, `asp`, `jq`
___

## Rollback-Patching

This script will attempt to install all updates EXCEPT security patches on a `eksctl` node-group for the given AWS profile.  The template files must be in the folder structure specified in the script which is the structure created in `deploy.sh` script.

Requirements: `awscli`, `asp`, `jq`
___

## Test

Testing script to test anything.....
___

## KMS-Create

YAML file used to update launch template
