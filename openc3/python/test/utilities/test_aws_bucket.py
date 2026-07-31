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

import unittest
from unittest.mock import MagicMock

from botocore.exceptions import ClientError

from openc3.utilities.aws_bucket import AwsBucket


class TestAwsBucketGetObject(unittest.TestCase):
    def setUp(self):
        self.bucket = AwsBucket()
        self.bucket.client = MagicMock()

    def error(self, code):
        return ClientError({"Error": {"Code": code, "Message": code}}, "GetObject")

    def test_returns_none_if_no_object(self):
        self.bucket.client.get_object.side_effect = self.error("NoSuchKey")
        self.assertIsNone(self.bucket.get_object("bucket", "nope"))

    # AWS S3 returns AccessDenied instead of NoSuchKey when the caller lacks s3:ListBucket
    def test_returns_none_if_access_is_denied(self):
        self.bucket.client.get_object.side_effect = self.error("AccessDenied")
        self.assertIsNone(self.bucket.get_object("bucket", "nope"))

    def test_raises_other_client_errors(self):
        self.bucket.client.get_object.side_effect = self.error("InternalError")
        with self.assertRaises(ClientError):
            self.bucket.get_object("bucket", "nope")
