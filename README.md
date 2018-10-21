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

```
Usage: ruby path/to/ecs-deploy.rb COMMAND [OPTIONS]

Commands:
  deploy    Deploy tasks from latest images.
  rollback  Rollback tasks to the images of previous version.

Options:
  --canary     Run canary deploy/rollback.
```

For canary deploy, run

```
ruby path/to/ecs-deploy.rb deploy --canary
```

For canary rollback, run

```
ruby path/to/ecs-deploy.rb rollback --canary
```

For deploy, run

```
ruby path/to/ecs-deploy.rb deploy
```

For rollback, run

```
ruby path/to/ecs-deploy.rb rollback
```

# Deployment

<img width="500" alt="Screen Shot 2018-10-21 at 16.19.16.png" src="https://qiita-image-store.s3.amazonaws.com/0/108729/7714b409-bce1-7276-3a43-1d3cfe8500c2.png">

## Canary Deploy

1. Build latest image from Dockerfile.
2. Push the image to ECR with timestamp and git commit hash tags.
3. Make new revision of task definition with the image.
4. Run one task with the task definition. This task is separated from service.
5. Add the private IP of the task to target group.

## Canary Rollback

1. Stop and destroy the canary deployed task.
2. Remove the IP from target group.

## Deploy

1. Update service using the latest revision of task definition.
2. Stop and destroy the canary deployed task.

## Rollback

1. Update service using the previous revision of task definition.

# Contributing
Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/ecs_deploy. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the Contributor Covenant code of conduct.
