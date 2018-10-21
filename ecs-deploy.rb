require "json"
require "yaml"

class EnvFileMissingError < StandardError; end

class ECSDeploy
  CANARY_STARTED_BY_TAG = "canary"

  def initialize
    validate_args

    @env = ENV["ENV"] || "prd"
    begin
      env = YAML.load_file("./env/#{@env}.yml")
    rescue Errno::ENOENT
      raise EnvFileMissingError
    end

    set_instance_variables(env)
    login_aws
  end

  def exec_command
    if    @command == "deploy"   && @is_canary
      canary_deploy
    elsif @command == "rollback" && @is_canary
      canary_rollback
    elsif @command == "deploy"   && !@is_canary
      deploy
    elsif @command == "rollback" && !@is_canary
      rollback
    end
  end

  # ruby path/to/ecs-deploy.rb deploy --canary
  def canary_deploy
    puts "-----> START canary deploy"
    image_name = push_latest_image
    task_definition = update_task_definition(image_name)
    new_task = run_task(task_definition, CANARY_STARTED_BY_TAG)
    task_arn = new_task["tasks"][0]["taskArn"]
    puts "-----> task ARN: #{task_arn}"

    # take several seconds to get IP
    while true
      private_ip = get_task_private_ip(task_arn)
      if !private_ip.nil?
        puts "-----> private IP: #{private_ip}"
        break
      end
      sleep(1)
    end

    add_task_to_target_group(private_ip)
    puts "-----> END canary deploy"
  end

  # ruby path/to/ecs-deploy.rb rollback --canary
  def canary_rollback
    puts "-----> START canary rollback"
    task_definition_arn = remove_canary_task
    deregister_task_definition(task_definition_arn)
    puts "-----> END canary rollback"
  end

  # ruby path/to/ecs-deploy.rb deploy
  def deploy
    puts "-----> START deploy"
    task_arn = get_task_arn(CANARY_STARTED_BY_TAG)
    task_definition_arn = get_task_definition_arn(task_arn)
    update_service(task_definition_arn)
    remove_canary_task
    puts "-----> END deploy"
  end

  # ruby path/to/ecs-deploy.rb rollback
  def rollback
    puts "-----> START rollback"
    latest_task_definiton = get_latest_task_definition
    deregister_task_definition(latest_task_definiton)
    previous_task_definiton = get_latest_task_definition
    update_service(previous_task_definiton)
    puts "-----> END rollback"
  end

  private

  def show_commands
    commands = <<-EOS
Usage: ruby path/to/ecs-deploy.rb COMMAND [OPTIONS]

Commands:
  deploy    Deploy tasks from latest images.
  rollback  Rollback tasks to the images of previous version.

Options:
  --canary     Run canary deploy/rollback.

    EOS
    puts commands
  end

  def set_instance_variables(env)
    @cluster = env["ecs"]["cluster_name"]
    @service = env["ecs"]["service_name"]
    @task    = env["ecs"]["task_definition_name"]
    @container_name = env["ecs"]["container_name"]
    @ecr_url = env["ecr"]["url"]
    @dockerfile_path = env["ecr"]["local_file_path"]
    @ecr_name = env["ecr"]["name"]
    @target_group_arn = env["elb"]["target_group_arn"]

    self.instance_variables.each do |attr|
      puts "-----> #{attr}: #{self.instance_variable_get(attr)}"
    end
  end

  def validate_args
    @command = ARGV[0]
    if @command != "deploy" && @command != "rollback"
      show_commands
      raise "the following arguments are required: command"
    end

    @is_canary = ARGV.include?("--canary")
  end

  def login_aws
    cmd = `aws ecr get-login --no-include-email --region ap-northeast-1`
    return `eval #{cmd}`
  end

  def get_ecr_image_name(tag)
    return "#{@ecr_url}/#{@ecr_name}:#{tag}"
  end

  def push_latest_image
    tag_timestamp = Time.now.strftime("%Y%m%d_%H%M")
    tag_git_commit_hash = `git rev-parse HEAD`
    tags = [tag_timestamp, tag_git_commit_hash]
    puts "-----> Push latest image. Tag: #{tags.join(", ")}"

    cmd_build = `docker build -t #{@ecr_name} #{@dockerfile_path}`
    tags.each do |tag|
      cmd = `
        docker tag #{@ecr_name}:latest #{get_ecr_image_name(tag)}
        docker push #{get_ecr_image_name(tag)}`
    end

    return get_ecr_image_name(tag_timestamp)
  end

  def get_task_definitions
    cmd = `aws ecs list-task-definitions \
      --family-prefix #{@task} \
      --sort DESC \
      --max-items 5`
    return JSON.parse(cmd)["taskDefinitionArns"]
  end

  def get_latest_task_definition
    return get_task_definitions[0]
  end

  def get_latest_task_definition_description
    latest_task_definition = get_latest_task_definition
    task_definition = `aws ecs describe-task-definition \
      --task-definition #{latest_task_definition} \
      | jq -r .taskDefinition`
    return JSON.parse(task_definition)
  end

  def get_task_definition_arn(task_arn)
    return get_task_description(task_arn)["tasks"][0]["taskDefinitionArn"]
  end

  def update_task_definition(image_name)
    puts "-----> Update task definition"
    task_definition = get_latest_task_definition_description
    container_definitions = task_definition["containerDefinitions"]

    new_container_definitions = []
    container_definitions.each do |container|
      container["image"] = image_name if container["name"] == "#{@container_name}"
      new_container_definitions << container
    end

    new_revision = `aws ecs register-task-definition \
      --family #{@task} \
      --task-role-arn #{task_definition["taskRoleArn"]} \
      --execution-role-arn #{task_definition["executionRoleArn"]} \
      --network-mode #{task_definition["networkMode"]} \
      --volumes '#{task_definition["volumes"].to_json}' \
      --cpu #{task_definition["cpu"]} \
      --memory #{task_definition["memory"]} \
      --requires-compatibilities #{task_definition["requiresCompatibilities"][0]} \
      --container-definitions '#{new_container_definitions.to_json}'`

    new_task_definition_arn = JSON.parse(new_revision)["taskDefinition"]["taskDefinitionArn"]
    puts "-----> New task definition arn: #{new_task_definition_arn}"

    return new_task_definition_arn
  end

  def deregister_task_definition(task_identifier)
    puts "-----> Deregister task definition: #{task_identifier}"
    cmd = `aws ecs deregister-task-definition \
      --task-definition #{task_identifier}`
    return cmd
  end

  def update_service(task_definition)
    puts "-----> Update service"
    puts "-----> Task definition: #{task_definition}"
    cmd = `aws ecs update-service \
      --cluster #{@cluster} \
      --service #{@service} \
      --task-definition #{task_definition} \
      --force-new-deployment`
    return cmd
  end

  def get_service_description
    cmd = `aws ecs describe-services \
      --cluster #{@cluster} \
      --services #{@service}`
    return JSON.parse(cmd)["services"][0]
  end

  def run_task(task_definition, started_by_tag)
    puts "-----> Run new task"
    service_desc = get_service_description
    conf = service_desc["networkConfiguration"]["awsvpcConfiguration"]
    cmd = `aws ecs run-task \
      --cluster #{@cluster} \
      --task-definition #{task_definition} \
      --network-configuration "awsvpcConfiguration={\
        subnets=[#{conf["subnets"].join(",")}],\
        securityGroups=[#{conf["securityGroups"].join(",")}],\
        assignPublicIp="DISABLED"}" \
      --launch-type FARGATE \
      --started-by #{started_by_tag}`
    return JSON.parse(cmd)
  end

  def stop_task(task_identifier)
    # identifier is task_id or task_arn
    puts "-----> Stop task #{task_identifier}"
    cmd = `aws ecs stop-task \
      --cluster #{@cluster} \
      --task #{task_identifier}`
    return cmd
  end

  def remove_canary_task
    puts "-----> Remove canary task"
    task_arn = get_task_arn(CANARY_STARTED_BY_TAG)
    private_ip = get_task_private_ip(task_arn)
    remove_task_from_target_group(private_ip)
    stop_task(task_arn)
    return get_task_definition_arn(task_arn)
  end

  def get_task_arn(started_by_tag)
    cmd = `aws ecs list-tasks \
      --cluster #{@cluster} \
      --started-by #{started_by_tag}`
    return JSON.parse(cmd)["taskArns"][0]
  end

  def get_task_description(task_identifier)
    # identifier is task_id or task_arn
    task_description = `aws ecs describe-tasks \
      --cluster #{@cluster} \
      --tasks #{task_identifier}`
    return JSON.parse(task_description)
  end

  def get_task_private_ip(task_identifier)
    task_description = get_task_description(task_identifier)

    begin
      task_details = task_description["tasks"][0]["attachments"][0]["details"]
      ip_info = task_details.select {|e| e["name"] == "privateIPv4Address"}
      private_ip = ip_info[0]["value"]
      return private_ip
    rescue
      return nil
    end
  end

  def add_task_to_target_group(private_ip)
    puts "-----> Add #{private_ip} to the target group"
    cmd = `aws elbv2 register-targets \
      --target-group-arn #{@target_group_arn} \
      --targets Id=#{private_ip},Port=8000`
    return cmd
  end

  def remove_task_from_target_group(private_ip)
    puts "-----> Remove #{private_ip} from the target group"
    cmd = `aws elbv2 deregister-targets \
      --target-group-arn #{@target_group_arn} \
      --targets Id=#{private_ip},Port=8000`
    return cmd
  end
end

ecs = ECSDeploy.new()
ecs.exec_command
