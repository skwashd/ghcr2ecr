import base64
import hashlib
import hmac
import json
import os
import shlex

import boto3

WEBHOOK_SECRET = None


def verify_signature(header: str, body: str, webhook_secret: str) -> bool:
    (algo, signature) = header.split("=")
    if algo != "sha256":
        return False

    mac = hmac.new(bytes(webhook_secret, "utf-8"), body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(mac, signature)


def load_secret(name):
    ssm = boto3.client("ssm")
    return json.loads(
        ssm.get_parameter(Name=name, WithDecryption=True)["Parameter"]["Value"]
    )


def trigger_build(org_name, image_name):
    project_name = f"{org_name}SyncImages"
    cb = boto3.client("codebuild")
    response = cb.start_build(
        projectName=project_name,
        environmentVariablesOverride=[
            {
                "name": "IMAGE_NAME",
                "value": image_name,
                "type": "PLAINTEXT",
            }
        ],
    )
    build_id = response["build"]["id"]
    return build_id


def handler(event, context):

    global WEBHOOK_SECRET
    if not WEBHOOK_SECRET:
        WEBHOOK_SECRET = load_secret(f"/{os.environ.get('AWS_LAMBDA_FUNCTION_NAME')}/WEBHOOK_SECRET")

    signature = event["headers"].get("X-Hub-Signature-256")
    if not signature or not verify_signature(
        signature, event["body"].encode(), WEBHOOK_SECRET
    ):
        return {"statusCode": 401, "body": "Unauthorized"}

    event_type = event["headers"].get("X-GitHub-Event")
    if event_type == "ping":
        return {"statusCode": 200, "body": "pong!"}

    body = json.loads(event["body"])

    if event_type != "package_v2" or body["action"] not in [
        "create",
        "published",
        "updated",
    ]:
        return {"statusCode": 400, "body": "Bad Request"}

    if body["package"]["ecosystem"] != "CONTAINER":
        return {"statusCode": 200, "body": "We don't care"}

    org_name = body["organization"]["login"]
    image_name = body["package"]["name"]
    if shlex.quote(org_name) != org_name or shlex.quote(image_name) != image_name:
        return {"statusCode": 403, "body": "Forbidden"}

    build_id = trigger_build(org_name, image_name)
    return {"statusCode": 200, "body": f'{"build_id", f"{build_id}"}'}
