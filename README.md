# ecs-deploy
Simple script for initiating blue-green/canary deployments on Amazon Elastic Container Service (ECS). This script can be used **only for Fargate type**.

# Installation

Clone this repository to the random path.

```
git clone https://github.com/HiromuMasuda/ecs-deploy.git
```

Move the main file to your app directory.

```
cp path/to/ecs-deploy/ecs-deploy.rb path/to/yourapp
```

Make env directory and env file, file names are the environment names of your app.

```
YourAppDir/
  |-- YourAppFile
  |-- ecs-deploy.rb
  |-- env/
    |-- prd.yml
    |-- stg.yml
    |-- dev.yml
```

Set variables in yaml file like below.

```yaml
ecs:
  cluster_name: sample_app_prd
  service_name: sample_app_prd
  task_definition_name: sample_app_prd
  container_name: sample_app
ecr:
  url: xxx.dkr.ecr.ap-northeast-1.amazonaws.com
  name: sample_app
  local_file_path: ./
elb:
  target_group_arn: arn:aws:elasticloadbalancing:ap-northeast-1:xxx:targetgroup/xxx/xxx
```

Finally install jq command.


# Usage


# Deployment


# Contributing


