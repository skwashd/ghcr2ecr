#!/usr/bin/env python3

import logging
import os
import sys

import boto3
import botocore.exceptions
import docker
import requests


# Configure logging.
logging.getLogger().setLevel(logging.INFO)
logging.StreamHandler(sys.stdout)


class GitHubError(Exception):
    """Generic GitHub error."""

    pass


class GitHubUnauthorizedError(GitHubError):
    """GitHub access requires authentication error."""

    pass


class GitHubForbiddenError(GitHubError):
    """GitHub access forbidden error."""

    pass


class GitHubNotFoundError(GitHubError):
    """GitHub resource not found error."""

    pass


class GitHubClient:
    """Simple GitHub client class."""

    def __init__(self, token: str, org: str):
        self.token = token
        self.org = org

    def _generate_url(self, path: str):
        """Generate API URLs in a consistent manner."""
        return f"https://api.github.com{path}"

    def _request(self, method: str, url: str, payload: dict = None):
        headers = {
            "Accept": "application/vnd.github.v3+json",
            "Authorization": f"token {self.token}",
        }

        response = requests.request(method, url, json=payload, headers=headers)
        try:
            response.raise_for_status()
        except requests.exceptions.HTTPError as e:
            status_code = response.status_code
            if status_code == 401:
                raise GitHubUnauthorizedError(str(e))
            elif status_code == 403:
                raise GitHubForbiddenError(str(e))
            elif status_code == 404:
                raise GitHubNotFoundError(str(e))

            raise GitHubError(str(e))

        rel_next = response.links.get("next", {})
        data = response.json()
        if rel_next:
            url = rel_next.get("url")
            try:
                more_data = self._request("GET", url)
            except GitHubError:
                return

            if more_data:
                data += more_data

        return data

    def send_request(self, method: str, path: str, payload: dict = None):
        return self._request(method, self._generate_url(path), payload)

    def fetch_package_versions(self, pkg_type: str, package: str):
        path = f"/orgs/{self.org}/packages/{pkg_type}/{package}/versions"
        return self.send_request("GET", path)


def get_ghcr_tags(token: str, org: str, repo: str):
    """Fetch all the tags and associated hashes for a GHCR image repo."""
    gh = GitHubClient(token, org)
    ghcr_tags = {}
    for image in gh.fetch_package_versions("container", repo):
        image_hash = image["name"]
        for tag in image["metadata"]["container"]["tags"]:
            ghcr_tags[tag] = image_hash
            logging.info("Found %s on GitHub", tag)
    return ghcr_tags


def get_ecr_tags(ecr, repo: str):
    tags = {}
    image = ecr.describe_images(repositoryName=repo)
    if image["imageDetails"]:
        for details in image["imageDetails"]:
            image_hash = details["imageDigest"]
            for tag in details["imageTags"]:
                tags[tag] = image_hash
                logging.info("Found %s on AWS", tag)

    return tags


def get_aws_info() -> str:
    my_session = boto3.session.Session()
    return (
        my_session.region_name,
        boto3.client("sts").get_caller_identity().get("Account"),
    )


def ecr_repo_exists(ecr, name):
    try:
        repos = ecr.describe_repositories(repositoryNames=[name])
        return (
            repos.get("repositories", False)
            and repos["repositories"][0]["repositoryName"] == name
        )
    except botocore.exceptions.ClientError:
        pass
    return False


def ecr_create_repo(ecr, name):
    repo = ecr.create_repository(
        repositoryName=name,
        encryptionConfiguration={"encryptionType": "KMS", "kmsKey": "alias/aws/ecr"},
    ).get("repository")


def main(gh_token: str, gh_org: str, repo: str):
    logging.info("Syncing images for %s/%s", gh_org, repo)

    ecr = boto3.client("ecr")
    if not ecr_repo_exists(ecr, repo):
        logging.info("Creating ECR repo for %s", repo)
        ecr_create_repo(ecr, repo)

    (aws_region, aws_account_id) = get_aws_info()
    aws_repo = f"{aws_account_id}.dkr.ecr.{aws_region}.amazonaws.com/{repo}"
    ghcr_repo = f"ghcr.io/{gh_org}/{repo}"

    ghcr_tags = get_ghcr_tags(gh_token, gh_org, repo)
    ecr_tags = get_ecr_tags(ecr, repo)

    client = docker.from_env()
    for ghcr_tag in ghcr_tags:
        ecr_tag = ecr_tags.get(ghcr_tag)
        if not ecr_tag or ecr_tag != ghcr_tags[ghcr_tag]:
            local_img = client.images.pull(ghcr_repo, ghcr_tag)
            logging.info("Pulled %s", f"{ghcr_repo}:{ghcr_tag}")
            local_img.tag(aws_repo, ghcr_tag)
            logging.info("Tagged %s", f"{aws_repo}:{ghcr_tag}")
            client.images.push(aws_repo, ghcr_tag)
            logging.info("Pushed %s", f"{aws_repo}:{ghcr_tag}")


if __name__ == "__main__":
    github_org = sys.argv[1]
    repo = sys.argv[2]
    main(os.environ.get("GITHUB_TOKEN"), github_org, repo)
