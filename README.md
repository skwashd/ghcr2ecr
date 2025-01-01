# GitHub Container Registry to Amazon Elastic Container Registry Image Sync

## THIS PROJECT IS NO LONGER MAINTAINED

I created this before [AWS supported OIDC ffrom GitHub](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services). Don't waste your time with this project. Use OIDC instead.

## Old Docs

ghcr2ecr is a terraform module that sets up the tooling you need to push Docker
images from GitHub Container Registry (GHCR) to Amazon Elastic Container
Registry (ECR).

![GHCR2ECR "logo"](img/ghcr2ecr.png?raw=true)

ghcr2ecr sets everything up within GitHub and AWS. It can be run once and
forgotten if that's how you roll.

The module will configure an API Gateway that receives webhook notifications
from GitHub every time a new image is published to your organisation's container
repositories. The API Gateway triggers a Lambda function, that in turn triggers
CodeBuild. The build finds all the images in GHCR that don't exist in ECR. If
fetches the missing images and pushes them into ECR.

The flow is triggered when GitHub Actions pushes a new image in GHCR. The
project relies on the (as yet undocumented) organisation level package v2 events
emitted by GitHub.

Here is a high level overview of the full flow from creating a git commit to the
image being pushed to ECR.

![Visualisation of the flow of a change to container image as described in the
text above](img/flow.png?raw=true)

## Why don't You Just [Some Alternative]?

I know some of your are probably wondering why I’m not doing this another way.
The short answer is, because I think this is the most secure way to do it. One
of the biggest benefits of this approach is that we avoid having write
credentials for one system stored on another platform. There are no long lived
credentials with ECR write permissions floating around in your GitHub Actions.

For the longer version read my blog post [A Rube Goldberg Machine for
Container Workflows](https://www.davehall.com.au/blog/2021/05/31/rube-goldberg-machine-container-workflows).

## Quick Start
The easiest way to set this project up is to add the following configuration to your existing project:

```hcl
module "ghcr2ecr" {
  source       = "git@github.com:skwashd/ghcr2ecr.git"
  aws_region   = "us-east-1"
  github_org   = "my_org_name"
  github_token = "ghp_EXAMPLE_TOKEN"
}
```

For this to work you have to [configure your AWS
credentials](https://registry.terraform.io/providers/hashicorp/aws/latest/docs#authentication).

Next up you need to generate two GitHub tokens. **Do not use the same token for
both purposes.** The access will be over provisioned for both use cases.

The first GitHub token is the one used in the module configuration above.
Thistoken needs to have [`read:package`
scope](https://github.com/settings/tokens/new?scopes=read:packages).

The second token is used by terraform to configure the webhook. This token needs
the [`admin:org_hook`
scope](https://github.com/settings/tokens/new?scopes=admin:org_hook). This
should be used as an [environment variable for
authentication](https://registry.terraform.io/providers/integrations/github/latest/docs#authentication).

Now you should be set to run `terraform apply`. A minute or so after you
approve the changes everything should be provisioned.

The next time an image is pushed to GHCR it should be synced to AWS ECR.

In case you're wondering why the script executed by CodeBuild is fetched from
GitHub each time, this was primary done as I couldn't find a way to inline the
Python code in the `buildspec.yml` file. We use a sha256 integrity check to
ensure it hasn't been tampered with. If this makes you uncomfortable you can
override the `build_script_sha256` and `build_script_url` variables to use your
own buildscript hosted elsewhere.
