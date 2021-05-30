version: 0.2
env:
  environment:
    IMAGE_NAME: "set@runtime"
  parameter-store:
    GITHUB_TOKEN: "/codebuild/${project_name}/GITHUB_TOKEN"
phases:
  install:
    runtime-versions:
      python: 3.8
  pre_build:
    commands:
      - pip install boto3==1.17.78 docker==5.0.0 requests==2.25.1
      - curl -L ${build_script_url} -o /tmp/sync.py
      - echo "${build_script_sha256}  /tmp/sync.py" | sha256sum --check
      - chmod +x /tmp/sync.py
      - aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin ${aws_account_id}.dkr.ecr.$AWS_REGION.amazonaws.com
      - echo $GITHUB_TOKEN | docker login ghcr.io -u USERNAME --password-stdin
  build:
    commands:
      - /tmp/sync.py ${github_org} $IMAGE_NAME
  post_build:
    commands:
      - echo Sync complete

