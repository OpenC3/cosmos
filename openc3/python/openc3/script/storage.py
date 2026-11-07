# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
import base64
import io
import json
import os
import tempfile
import traceback

import requests

import openc3.script
from openc3.environment import OPENC3_SCOPE
from openc3.utilities.extract import *
from openc3.utilities.local_mode import LocalMode


OPENC3_CLOUD = os.environ.get("OPENC3_CLOUD") or "local"


def delete_target_file(path: str, scope: str = OPENC3_SCOPE):
    """Delete a file on a target

    Args:
        path (str) Path to a file in a target directory
        scope (str) Optional, defaults to env.OPENC3_SCOPE
    """
    try:
        # Only delete from the targets_modified
        delete_path = f"{scope}/targets_modified/{path}"
        endpoint = f"/openc3-api/storage/delete/{delete_path}"
        print(f"Deleting {delete_path}")
        # Pass the name of the ENV variable name where we pull the actual bucket name
        response = openc3.script.API_SERVER.request(
            "delete", endpoint, query={"bucket": "OPENC3_CONFIG_BUCKET"}, scope=scope
        )
        if not response or response.status_code != 200:
            raise Exception(f"Failed to delete {delete_path}")
    except Exception as error:
        raise Exception(f"Failed deleting {path} due to {traceback.format_exc()}") from error
    return None


def put_target_file(path: str, io_or_string: io.IOBase | str, scope: str = OPENC3_SCOPE):
    """Get a handle to write a target file

    Args:
        path (str) Path to a file in a target directory
        io_or_string (io | str) IO object or str object
        scope (str) Optional, defaults to env.OPENC3_SCOPE
    """
    if ".." in path:
        raise Exception(f"Disallowed path modifier '..' found in {path}")

    upload_path = f"{scope}/targets_modified/{path}"

    if LocalMode.local_only_name(path):
        # The local mode volume is only mounted in the cluster so from outside
        # write it through the API which never sends it to the bucket
        if not openc3.script.OPENC3_IN_CLUSTER:
            return _upload_api_file(upload_path, io_or_string, scope=scope)
        print(f"Writing local {upload_path}")
        LocalMode.put_target_file(upload_path, io_or_string, scope=scope)
        return None

    if os.getenv("OPENC3_LOCAL_MODE") and openc3.script.OPENC3_IN_CLUSTER:
        LocalMode.put_target_file(upload_path, io_or_string, scope=scope)
        if hasattr(io_or_string, "read"):  # not str or bytes
            io_or_string.seek(0)

    endpoint = f"/openc3-api/storage/upload/{upload_path}"
    result = _get_presigned_request(endpoint, scope=scope)
    print(f"Writing {upload_path}")

    # Try to put the file
    try:
        uri = _get_uri(result["url"])
        with requests.Session() as s:
            if hasattr(io_or_string, "read"):
                # TODO: Better way to get io size?
                io_or_string.seek(0, 2)  # Jump to end
                length = io_or_string.tell()
                io_or_string.seek(0)
                io_or_string = io_or_string.read()
            else:  # str or bytes
                length = len(io_or_string)
            result = s.put(
                uri,
                data=io_or_string,
                headers={"Content-Length": str(length)},
            )
            return result.content
    except Exception as error:
        raise Exception(f"Failed to write {upload_path} due to {traceback.format_exc()}") from error


def get_target_file(path: str, original: bool = False, scope: str = OPENC3_SCOPE):
    """Get a handle to access a target file

    Args:
        path (str): Path to a file in a target directory, e.g. "INST/procedures/test.rb"
        original (bool): Whether to get the original or modified file; defaults to False
        scope (str): Optional, defaults to env.OPENC3_SCOPE

    Return:
        (File | None)
    """
    # Local only targets only exist in the local mode volume so original doesn't apply
    if LocalMode.local_only_name(path):
        # The local mode volume is only mounted in the cluster so from outside
        # read it through the API which serves it from the volume
        if not openc3.script.OPENC3_IN_CLUSTER:
            return _get_api_file(f"targets_modified/{path}", scope=scope)
        return _get_local_file(path, scope=scope)

    part = "targets"
    if original is False:
        part += "_modified"
    # Loop to allow redo when switching from modified to original
    while True:
        try:
            if part == "targets_modified" and os.getenv("OPENC3_LOCAL_MODE"):
                file = _get_local_file(path, scope=scope)
                if file:
                    return file
            return _get_storage_file(f"{part}/{path}", scope=scope)
        except Exception:
            if part == "targets_modified":
                part = "targets"
                # redo
            else:
                return None


# These are helper methods ... should not be used directly


def _upload_api_file(path, io_or_string, bucket="OPENC3_CONFIG_BUCKET", scope=OPENC3_SCOPE):
    """Write a file through the API instead of a presigned URL"""
    data = io_or_string.read() if hasattr(io_or_string, "read") else io_or_string
    if isinstance(data, str):
        data = data.encode("utf-8")
    endpoint = f"/openc3-api/storage/upload_file/{path}"
    print(f"Writing {path}")
    response = openc3.script.API_SERVER.request(
        "put",
        endpoint,
        query={"bucket": bucket},
        data={"contents": base64.b64encode(data).decode("ascii")},
        json=True,
        scope=scope,
    )
    if not response or response.status_code != 200:
        raise RuntimeError(f"Failed to write {path}")
    return None


def _get_api_file(path, bucket="OPENC3_CONFIG_BUCKET", scope=OPENC3_SCOPE):
    """Read a file through the API instead of a presigned URL. Returns None if the file doesn't exist"""
    endpoint = f"/openc3-api/storage/download_file/{scope}/{path}"
    response = openc3.script.API_SERVER.request("get", endpoint, query={"bucket": bucket}, scope=scope)
    if response is not None and response.status_code == 404:
        return None
    if not response or response.status_code != 200:
        raise RuntimeError(f"Failed to read {scope}/{path}")
    print(f"Reading {scope}/{path}")
    file = tempfile.NamedTemporaryFile(mode="w+b")  # noqa: SIM115 - returned to caller
    file.write(base64.b64decode(response.json()["contents"]))
    file.seek(0)  # Rewind so the file is ready to read
    return file


def _get_local_file(path, scope=OPENC3_SCOPE):
    local_file = LocalMode.open_local_file(path, scope=scope)
    if not local_file:
        return None
    print(f"Reading local {scope}/targets_modified/{path}")
    file = tempfile.NamedTemporaryFile(mode="w+b")  # noqa: SIM115 - returned to caller
    try:
        file.write(local_file.read())
    finally:
        local_file.close()
    file.seek(0)  # Rewind so the file is ready to read
    return file


def _get_download_url(path: str, scope: str = OPENC3_SCOPE):
    """Get a download url for object in block storage

    Args:
        path (str) Path to a file in a target directory, e.g. "INST/procedures/test.rb"
        scope (str) Optional, defaults to env.OPENC3_SCOPE
    """
    if LocalMode.local_only_name(path):
        raise RuntimeError(
            f"{path} belongs to a local only target (OPENC3_LOCAL_ONLY_TARGETS) and has no bucket download URL"
        )
    targets = "targets_modified"  # First try targets_modified
    response = openc3.script.API_SERVER.request(
        "get",
        f"/openc3-api/storage/exists/{scope}/{targets}/{path}",
        query={"bucket": "OPENC3_CONFIG_BUCKET"},
        scope=scope,
    )

    if response.status_code != 200:
        targets = "targets"  # Next try targets
        response = openc3.script.API_SERVER.request(
            "get",
            f"/openc3-api/storage/exists/{scope}/{targets}/{path}",
            query={"bucket": "OPENC3_CONFIG_BUCKET"},
            scope=scope,
        )
        if response.status_code != 200:
            raise RuntimeError(f"File not found: '{path}' in scope: {scope} (download URL lookup)")

    endpoint = f"/openc3-api/storage/download/{scope}/{targets}/{path}"
    # external must be true because we're using this URL from the frontend
    result = _get_presigned_request(endpoint, external=True, scope=scope)
    return result["url"]


def _get_storage_file(path, bucket="OPENC3_CONFIG_BUCKET", scope=OPENC3_SCOPE):
    # Create Tempfile to store data
    file = tempfile.NamedTemporaryFile(mode="w+b")  # noqa: SIM115 - returned to caller

    endpoint = f"/openc3-api/storage/download/{scope}/{path}"
    result = _get_presigned_request(endpoint, bucket=bucket, scope=scope)
    print(f"Reading {scope}/{path}")

    # Try to get the file
    uri = _get_uri(result["url"])
    response = requests.get(uri)
    if response.status_code == 404:
        raise RuntimeError(f"File not found: '{path}' in scope: {scope} (storage download)")
    file.write(response.content)
    file.seek(0)
    return file


def _get_uri(url):
    if openc3.script.OPENC3_IN_CLUSTER:
        match OPENC3_CLOUD:
            case "local":
                bucket_url = os.environ.get("OPENC3_BUCKET_URL", "http://openc3-buckets:9000")
                return f"{bucket_url}{url}"
            case "aws":
                return f"https://s3.{os.getenv('AWS_REGION')}.amazonaws.com{url}"
            case "gcp":
                return f"https://storage.googleapis.com{url}"
            # when 'azure'
            case _:
                raise Exception(f"Unknown cloud {OPENC3_CLOUD}")
    else:
        return f"{openc3.script.API_SERVER.generate_url()}{url}"


def _get_presigned_request(endpoint, external=None, bucket="OPENC3_CONFIG_BUCKET", scope=OPENC3_SCOPE):
    if external or not openc3.script.OPENC3_IN_CLUSTER:
        response = openc3.script.API_SERVER.request("get", endpoint, query={"bucket": bucket}, scope=scope)
    else:
        response = openc3.script.API_SERVER.request(
            "get",
            endpoint,
            query={"bucket": bucket, "internal": True},
            scope=scope,
        )

    if not response or response.status_code != 201:
        raise Exception(f"Failed to get presigned URL for {endpoint}")
    return json.loads(response.text)
