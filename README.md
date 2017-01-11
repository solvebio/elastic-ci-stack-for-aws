<h1><img alt="Elastic CI Stack for AWS" src="https://cdn.rawgit.com/buildkite/elastic-ci-stack-for-aws/master/images/banner.png"></h1>

![Build status](https://badge.buildkite.com/d178ab942e2f606a83e79847704648437d82a9c5fdb434b7ae.svg?branch=master)

The Buildkite Elastic CI Stack gives you a private, autoscaling [Buildkite Agent](https://buildkite.com/docs/agent) cluster. Use it to parallelize legacy tests across hundreds of nodes, run tests and deployments for all your Linux-based services and apps, or run AWS ops tasks.

Features:

- All major AWS regions
- Configurable instance size
- Configurable number of buildkite agents per instance
- Configurable spot instance bid price
- Configurable auto-scaling based on build activity
- Docker and Docker Compose support
- Per-pipeline S3 secret storage (with SSE encryption support)
- Docker Registry push/pull support
- CloudWatch logs for system and buildkite agent events
- CloudWatch metrics from the Buildkite API
- Support for stable, unstable or experimental Buildkite Agent releases
- Create as many instances of the stack as you need
- Rolling updates to stack instances to reduce interruption

## Contents

<!-- toc -->

- [Getting Started](#getting-started)
- [What’s On Each Machine?](#whats-on-each-machine)
- [What Type of Builds Does This Support?](#what-type-of-builds-does-this-support)
- [Multiple Instances of the Stack](#multiple-instances-of-the-stack)
- [Autoscaling Configuration](#autoscaling-configuration)
- [Configuration Environment Variables](#configuration-environment-variables)
- [Build Secrets](#build-secrets)
- [Docker Registry Support](#docker-registry-support)
- [Versions](#versions)
- [Updating Your Stack](#updating-your-stack)
- [CloudWatch Metrics](#cloudwatch-metrics)
- [Reading Instance and Agent Logs](#reading-instance-and-agent-logs)
- [Optimizing for Slow Docker Builds](#optimizing-for-slow-docker-builds)
- [Security](#security)
- [Questions?](#questions)
- [Releasing](#releasing)
- [Licence](#licence)

<!-- tocstop -->

## Getting Started

See the [Elastic CI Stack for AWS guide](https://buildkite.com/docs/guides/elastic-ci-stack-aws) for a step-by-step guide, or jump straight in:

[![Launch Buildkite AWS Stack v1.1.1](https://cdn.rawgit.com/buildkite/cloudformation-launch-stack-button-svg/master/launch-stack.svg)](https://console.aws.amazon.com/cloudformation/home#/stacks/new?stackName=buildkite&templateURL=https://s3.amazonaws.com/buildkite-aws-stack/v1.1.1/aws-stack.json)

Current version is v1.1.1. See [Releases](https://github.com/buildkite/elastic-ci-stack-for-aws/releases) for older releases, or [Versions](#versions) for development version

> Although the stack will create it's own VPC by default, we highly recommend following best practice by setting up a separate development AWS account and using role switching and consolidated billing—see the [Delegate Access Across AWS Accounts tutorial](http://docs.aws.amazon.com/IAM/latest/UserGuide/tutorial_cross-account-with-roles.html) for more information.

If you'd like to use the [AWS CLI](https://aws.amazon.com/cli/), download [`config.json.example`](config.json.example), rename it to `config.json`, and then run the below command:

```bash
aws cloudformation create-stack \
  --output text \
  --stack-name buildkite \
  --template-url "https://s3.amazonaws.com/buildkite-aws-stack/v1.1.1/aws-stack.json" \
  --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
  --parameters $(cat config.json)
```

If you’d prefer to use this repo or build it yourself, clone it and run the following commands:

```bash
# To set up your local environment and build a template based on public AMIs
make setup download-mappings build

# Or, to set things up locally and create the stack on AWS
make create-stack

# You can use any of the AWS* environment variables that the aws-cli supports
AWS_PROFILE="some-profile" make create-stack

# You can also use aws-vault or similar
aws-vault exec some-profile -- make create-stack
```

Adding extra tags to the stack (including the EC2 instances) can be done via `extra_tags.json` (see [`extra_tags.json.example`](extra_tags.json.example) for usage).

Next up you will need to upload source control credentials to the s3 bucket that you specified for `SecretsBucket` parameter. Check [Build Secrets](#buildsecrets) further down.


## What’s On Each Machine?

* [Amazon Linux 2016.09.1](https://aws.amazon.com/amazon-linux-ami/)
* [Buildkite Agent](https://buildkite.com/docs/agent)
* [Docker 1.12.5](https://www.docker.com)
* [Docker Compose 1.9.0](https://docs.docker.com/compose/)
* [aws-cli](https://aws.amazon.com/cli/) - useful for performing any ops-related tasks
* [jq](https://stedolan.github.io/jq/) - useful for manipulating JSON responses from cli tools such as aws-cli or the Buildkite API
* [docker-gc](https://github.com/spotify/docker-gc) - removes old docker images

## What Type of Builds Does This Support?

This stack is designed to run your builds in a share-nothing pattern similar to the [12 factor application principals](http://12factor.net):

* Each project should encapsulate it's dependencies via Docker and Docker Compose
* Build pipeline steps should assume no state on the machine (and instead rely on [build meta-data](https://buildkite.com/docs/guides/build-meta-data), [build artifacts](https://buildkite.com/docs/guides/artifacts) or S3)
* Secrets are configured via environment variables exposed using the S3 secrets bucket

By following these simple conventions you get a scaleable, repeatable and source-controlled CI environment that any team within your organization can use.

## Multiple Instances of the Stack

If you need to optimize pipelines for your types of applications you can create multiple stack with different configurations, each with a different [Agent Queue](https://buildkite.com/docs/agent/queues).

For example, you could have a `builders` stack that provides always on machines with warm Docker caches for building and pushing to a Docker registry at the start of a CI run. Or you could have a single `t2.nano` stack that is used for lightning fast `buildkite-agent pipeline upload` jobs.

Because each stack can run in a different agent queue, and each one self-contained (potentially in completely different AWS accounts), you're free to experiment without interrupting existing builds.

## Autoscaling Configuration

If you provided a `BuildkiteApiAccessToken` your build agents will autoscale. Autoscaling is designed to scale up quite quickly and then gradually scale down. Scaling up happens when there are scheduled jobs exist that are waiting for agents. Scaling down happens when there are no more running jobs.

See [the autoscale.yml template](templates/autoscale.yml) for more details, or the [Buildkite Metrics Publisher](https://github.com/buildkite/buildkite-cloudwatch-metrics-publisher) project for how metrics are collected. 

## Configuration Environment Variables

The following environment variables can be set on the Buildkite pipeline, or individual build step, to customize the behaviour of the stack:

* `BUILDKITE_SECRETS_BUCKET` - the name of the S3 bucket where secrets are stored. Default: the value set in the stack parameter when the stack was created. Example: `my-secrets-bucket`
* `BUILDKITE_SECRETS_PREFIX` - the folder within the secrets bucket. Default: the build pipeline's slug. Example: `my-great-pipeline`
* `SSH_KEY_NAME` - the filename of the SSH key inside this pipeline’s folder in the secrets bucket. Default: `private_ssh_key`. Example: `other_ssh_key`
* `SHARED_SSH_KEY_NAME` - the filename of the SSH key in the root of the secrets bucket if there's no pipeline-specific SSH key present. Default: `private_ssh_key`. Example: `other_ssh_key`

## Build Secrets

The stack refers to a `SecretsBucket` parameter which will allow your build agents to automatically get access to SSH private keys and environment hooks for exposing environment variables to builds. The stack doesn't create the bucket for you, you need to do this yourself, but it does give read access to the build machines. 

The secrets bucket can contain the following files:

* `/env` - An optional bash script to use as a global [agent environment hook](https://buildkite.com/docs/agent/hooks)
* `/private_ssh_key` - An optional private key to use for Git SSH operations when there is no pipeline-specific key present
* `/{pipeline-slug}/env` - An optional bash script to use as an [agent environment hook](https://buildkite.com/docs/agent/hooks)
* `/{pipeline-slug}/private_ssh_key` - An optional pipeline-specific private key to use for Git SSH operations

These files are encrypted using [Amazon's KMS Service](https://aws.amazon.com/kms/). See the [Security](#security) section for more details.

Here's an example that shows how to generate a private SSH key, and upload it with KMS encryption to an S3 bucket:

```bash
# generate a deploy key for your project
ssh-keygen -t rsa -b 4096 -f id_rsa_buildkite
pbcopy < id_rsa_buildkite.pub # paste this into your github deploy key

aws s3 cp --acl private --sse aws:kms id_rsa_buildkite "s3://${SecretsBucket}/private_ssh_key" 
```

If you really want to disable KMS encryption, you can set `BUILDKITE_USE_KMS=false`.

## Docker Registry Support

If you want to push or pull from registries such as [Docker Hub](https://hub.docker.com/) or [Quay](https://quay.io/) you can use the `env` file in your secrets bucket to export the following environment variables:

* `DOCKER_LOGIN_USER="the-user-name"`
* `DOCKER_LOGIN_PASSWORD="the-password"`
* `DOCKER_LOGIN_SERVER=""` - optional. By default it will log into Docker Hub

Setting these will perform a `docker login` before each pipeline step is run, allowing you to `docker push` to them from within your build scripts.

If you are using [Amazon ECR](https://aws.amazon.com/ecr/) you can set the `ECRAccessPolicy` parameter to the stack to either `readonly`, `poweruser`, or `full` depending on [the access level you want](http://docs.aws.amazon.com/AmazonECR/latest/userguide/ecr_managed_policies.html) your builds to have

You can disable this in individual pipelines by setting `AWS_ECR_LOGIN=false`.

If you want to login to an ECR server on another AWS account, you can set `AWS_ECR_LOGIN_REGISTRY_IDS="id1,id2,id3"`.

## Versions

We recommend running the latest release, which is a url in the form of `https://s3.amazonaws.com/buildkite-aws-stack/${VERSION}/aws-stack.json` that can be found on the [releases page](https://github.com/buildkite/elastic-ci-stack-for-aws/releases).

The latest build of the stack is published to `https://s3.amazonaws.com/buildkite-aws-stack/aws-stack.json`, along with a version for each commit in the form of `https://s3.amazonaws.com/buildkite-aws-stack/master/${COMMIT}.aws-stack.json`. 

Branches are published in the form of `https://s3.amazonaws.com/buildkite-aws-stack/${BRANCH}/aws-stack.json`. 

## Updating Your Stack

To update your stack to the latest version use CloudFormation’s stack update tools with one of the urls in the [Versions](#versions) section.

Prior to updating, it's a good idea to set the desired instance size on the AutoscalingGroup to 0 manually. 

## CloudWatch Metrics

Metrics are calculated every minute from the Buildkite API using a lambda function. 

<img width="544" alt="cloudwatch" src="https://cloud.githubusercontent.com/assets/153/16836158/85abdbc6-49ff-11e6-814c-eaf2400e8333.png">

You’ll find the stack’s metrics under "Custom Metrics > Buildkite" within CloudWatch.

## Reading Instance and Agent Logs

Each instance streams both system messages and Buildkite Agent logs to CloudWatch Logs under two log groups:

* `/var/log/messages` - System logs
* `/var/log/buildkite-agent.log` - Buildkite Agent logs
* `/var/log/docker` - Docker daemon logs
* `/var/log/elastic-stack.log` - Boot process logs

Within each stream the logs are grouped by instance id.

To debug an agent first find the instance id from the agent in Buildkite, head to your [CloudWatch Logs Dashboard](https://console.aws.amazon.com/cloudwatch/home?#logs:), choose either the system or Buildkite Agent log group, and then search for the instance id in the list of log streams.

## Optimizing for Slow Docker Builds

For large legacy applications the Docker build process might take a long time on new instances. For these cases it’s recommended to create an optimized "builder" stack which doesn't scale down, keeps a warm docker cache and is responsible for building and pushing the application to Docker Hub before running the parallel build jobs across your normal CI stack.

An example of how to set this up:

1. Create a Docker Hub repository for pushing images to
1. Update the pipeline’s `env` hook in your secrets bucket to perform a `docker login`
1. Create a builder stack with its own queue (i.e. `elastic-builders`), making sure to use `beta` agents so you can use the [Docker Compose Buildkite Plugin](https://github.com/buildkite-plugins/docker-compose-buildkite-plugin) and [pre-building](https://github.com/buildkite-plugins/docker-compose-buildkite-plugin#pre-building-the-image)

Here is an example build pipeline based on a production Rails application:

```yaml
steps:
  - name: ":docker: :package:"
    plugins:
      docker-compose:
        build: app
        image-repository: my-docker-org/my-repo
    agents:
      queue: elastic-builders
  - wait
  - name: ":hammer:"
    command: ".buildkite/steps/tests"
    plugins:
      docker-compose:
        run: app
    agents:
      queue: elastic
    parallelism: 75
```

See [Issue 81](https://github.com/buildkite/elastic-ci-stack-for-aws/issues/81) for ideas on other solutions (contributions welcome!).

## Security

This repository hasn't been reviewed by security researchers so exercise caution and careful thought with what credentials you make available to your builds.

Anyone with commit access to your codebase (including third-party pull-requests if you've enabled them in Buildkite) will have access to your secrets bucket files.

Also keep in mind the EC2 HTTP metadata server is available from within builds, which means builds act with the same IAM permissions as the instance.

## Questions?

Feel free to drop an email to support@buildkite.com with questions, or checkout the `#aws-stack` and `#aws` channels in [Buildkite Slack](https://chat.buildkite.com/).

## Releasing

* Create and push `v${VERSION}` tag (e.g. `v10.0`)
* Upload stack JSON and mapping YML artifacts to `buildkite-aws-stack` S3 bucket
* Create GitHub release (following previous release as a template) w/ stack JSON and mapping YML attached.

## Licence

See [Licence.md](Licence.md) (MIT)
