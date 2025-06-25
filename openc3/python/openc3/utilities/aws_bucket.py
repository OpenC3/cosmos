# Copyright 2023 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError, WaiterError
from openc3.utilities.bucket import Bucket
from openc3.environment import *
import time

aws_arn = OPENC3_AWS_ARN_PREFIX
s3_config = Config(s3={"addressing_style": "path"})
if OPENC3_BUCKET_URL:
    s3_endpoint_url = OPENC3_BUCKET_URL
elif OPENC3_DEVEL:
    s3_endpoint_url = "http://127.0.0.1:9000"
else:
    s3_endpoint_url = "http://openc3-minio:9000"

if OPENC3_CLOUD == "local":
    s3_session = boto3.session.Session(
        aws_access_key_id=OPENC3_BUCKET_USERNAME,
        aws_secret_access_key=OPENC3_BUCKET_PASSWORD,
        region_name="us-east-1",
    )
else:  # AWS
    s3_endpoint_url = f"https://s3.{AWS_REGION}.amazonaws.com"
    s3_session = boto3.session.Session(region_name=AWS_REGION)

class AwsBucket(Bucket):
    CREATE_CHECK_COUNT = 100  # 10 seconds

    def __init__(self):
        # Check whether the session is a real Session or a MockS3
        # print(f"\nAwsBucket INIT session:{s3_session}\n")
        self.client = s3_session.client("s3", endpoint_url=s3_endpoint_url, config=s3_config)

    def create(self, bucket):
        if not self.exist(bucket):
            self.client.create_bucket(Bucket=bucket)
            count = 0
            while True:
                time.sleep(0.1)
                count += 1
                if self.exist(bucket) or count > self.CREATE_CHECK_COUNT:
                    break
        return bucket

    def ensure_public(self, bucket):
        if OPENC3_NO_BUCKET_POLICY is None:
            policy = """{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:GetBucketLocation",
        "s3:ListBucket"
      ],
      "Effect": "Allow",
      "Principal": {
        "AWS": [
          "*"
        ]
      },
      "Resource": ["""
            policy = policy + f'\n        "{aws_arn}:s3:::{bucket}"'
            policy = (
                policy
                + """
      ],
      "Sid": ""
    },
    {
      "Action": [
        "s3:GetObject"
      ],
      "Effect": "Allow",
      "Principal": {
        "AWS": [
          "*"
        ]
      },
      "Resource": ["""
            )
            policy = policy + f'\n        "{aws_arn}:s3:::{bucket}/*"'
            policy = (
                policy
                + """
      ],
      "Sid": ""
    }
  ]
}"""
            )
            self.client.put_bucket_policy(Bucket=bucket, Policy=policy, ChecksumAlgorithm="SHA256")

    def exist(self, bucket):
        try:
            self.client.head_bucket(Bucket=bucket)
            return True
        except ClientError:
            return False

    def delete(self, bucket):
        if self.exist(bucket):
            self.client.delete_bucket(Bucket=bucket)

    def get_object(self, bucket, key, path=None):
        try:
            if path:
                response = self.client.get_object(Bucket=bucket, Key=key)
                with open(path, "wb") as f:
                    f.write(response["Body"].read())
                return response
            else:
                return self.client.get_object(Bucket=bucket, Key=key)
        # If the key is not found return nil
        except ClientError:
            return None

    def list_objects(self, bucket, prefix=None, max_request=1000, max_total=100_000):
        try:
            result = []
            kw_args = {"Bucket": bucket, "MaxKeys": max_request}
            if prefix:
                kw_args["Prefix"] = prefix
            while True:
                resp = self.client.list_objects_v2(**kw_args)
                if "Contents" in resp:
                    result = result + resp["Contents"]
                if len(result) >= max_total:
                    break
                if not resp["IsTruncated"]:
                    break
                kw_args["ContinuationToken"] = resp["NextContinuationToken"]
            # Array  of objects with key and size methods
            return result
        except ClientError:
            raise Bucket.NotFound(f"Bucket '{bucket}' does not exist.")

    # Lists the files under a specified path
    def list_files(self, bucket, path, only_directories=False, metadata=False):
        try:
            # Trailing slash is important in AWS S3 when listing files
            # See https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/S3/Types/ListObjectsV2Output.html#common_prefixes-instance_method
            if path[-1] != "/":
                path += "/"
            # If we're searching for the root then kill the path or AWS will return nothing
            if path == "/":
                path = None

            result = []
            dirs = []
            files = []
            kw_args = {"Bucket": bucket, "MaxKeys": 1000, "Delimiter": "/"}
            if path:
                kw_args["Prefix"] = path

            while True:
                resp = self.client.list_objects_v2(**kw_args)
                if "CommonPrefixes" in resp:
                    for item in resp["CommonPrefixes"]:
                        # If path was DEFAULT/targets_modified/ then the
                        # results look like DEFAULT/targets_modified/INST/
                        dirs.append(item["Prefix"].split("/")[-2])
                if only_directories:
                    result = dirs
                else:
                    if "Contents" in resp:
                        for aws_item in resp["Contents"]:
                            item = {
                                "name": aws_item["Key"].split("/")[-1],
                                "modified": aws_item["LastModified"],
                                "size": aws_item["Size"],
                            }
                            if metadata:
                                item["metadata"] = self.head_object(bucket=bucket, key=aws_item["Key"])
                            files.append(item)
                    result = (dirs, files)
                if not resp["IsTruncated"]:
                    break
                kw_args["ContinuationToken"] = resp["NextContinuationToken"]
            return result
        except ClientError:
            raise Bucket.NotFound(f"Bucket '{bucket}' does not exist.")

    # get metadata for a specific object
    def head_object(self, bucket, key):
        try:
            return self.client.head_object(Bucket=bucket, Key=key)
        except ClientError:
            raise Bucket.NotFound(f"Object '{bucket}/{key}' does not exist.")

    # put_object fires off the request to store but does not confirm
    def put_object(self, bucket, key, body, content_type=None, cache_control=None, metadata=None):
        kw_args = {
            "Bucket": bucket,
            "Key": key,
            "Body": body,
            "ChecksumAlgorithm": "SHA256",
        }
        if content_type:
            kw_args["ContentType"] = content_type
        if cache_control:
            kw_args["CacheControl"] = cache_control
        if metadata:
            kw_args["Metadata"] = metadata
        return self.client.put_object(**kw_args)

    # @returns [Boolean] Whether the file exists
    def check_object(self, bucket, key, retries=True):
        if retries:
            try:
                s3_object_exists_waiter = self.client.get_waiter("object_exists")
                s3_object_exists_waiter.wait(
                    Bucket=bucket,
                    Key=key,
                    WaiterConfig={"Delay": 0.1, "MaxAttempts": 30},
                )
                return True
            except WaiterError:
                return False
        else:
            try:
                self.head_object(bucket, key)
                return True
            except Bucket.NotFound:
                return False

    def delete_object(self, bucket, key):
        self.client.delete_object(Bucket=bucket, Key=key)

    def delete_objects(self, bucket, keys):
        def method(key):
            return {"Key": key}

        key_list = list(map(method, keys))
        return self.client.delete_objects(Bucket=bucket, Delete={"Objects": key_list})

    def presigned_request(self, bucket, key, method, internal=True):
        prefix = "/" if internal else "/files/"

        fields = None
        if method == "get_object":
            url = self.client.generate_presigned_url("get_object", Params={"Bucket": bucket, "Key": key})
        else:  # put_object
            response = self.client.generate_presigned_post(bucket, key)
            url = response["url"]
            fields = response["fields"]

        url = prefix + "/".join(url.split("/")[3:])
        return {"url": url, "fields": fields}
