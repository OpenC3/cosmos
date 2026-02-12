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

import importlib
import inspect
import warnings

from openc3.environment import OPENC3_CLOUD


# Interface class implemented by each cloud provider: AWS, GCS, Azure
class Bucket:
    # Raised when the underlying bucket does not exist
    class NotFoundError(Exception):
        pass

    @classmethod
    def get_client(cls):
        if not OPENC3_CLOUD:
            raise RuntimeError("OPENC3_CLOUD environment variable is required")
        # Base is AwsBucket which works with S3-compatible storage (versitygw), Enterprise implements additional
        bucket_class = OPENC3_CLOUD.capitalize() + "Bucket"
        my_module = None
        try:
            my_module = importlib.import_module("." + OPENC3_CLOUD.lower() + "_bucket", "openc3.utilities")
        # If the file doesn't exist try the Enterprise module
        except ModuleNotFoundError:
            my_module = importlib.import_module("." + OPENC3_CLOUD.lower() + "_bucket", "openc3enterprise.utilities")
        return getattr(my_module, bucket_class)()

    @classmethod
    def getClient(cls):  # noqa: N802
        """Deprecated: Use get_client() instead. This camelCase method is provided for backwards compatibility."""
        warnings.warn(
            "Bucket.getClient() is deprecated, use Bucket.get_client() instead",
            DeprecationWarning,
            stacklevel=2
        )
        return cls.get_client()

    def create(self, bucket):
        raise NotImplementedError(
            f"{self.__class__.__name__} has not implemented method '{inspect.currentframe().f_code.co_name}'"
        )

    def ensure_public(self, bucket):
        raise NotImplementedError(
            f"{self.__class__.__name__} has not implemented method '{inspect.currentframe().f_code.co_name}'"
        )

    def exist(self, bucket):
        raise NotImplementedError(
            f"{self.__class__.__name__} has not implemented method '{inspect.currentframe().f_code.co_name}'"
        )

    def delete(self, bucket):
        raise NotImplementedError(
            f"{self.__class__.__name__} has not implemented method '{inspect.currentframe().f_code.co_name}'"
        )

    def get_object(self, bucket, key, path=None, range=""):
        raise NotImplementedError(
            f"{self.__class__.__name__} has not implemented method '{inspect.currentframe().f_code.co_name}'"
        )

    def list_objects(self, bucket, prefix=None, max_request=None, max_total=None):
        raise NotImplementedError(
            f"{self.__class__.__name__} has not implemented method '{inspect.currentframe().f_code.co_name}'"
        )

    def list_files(self, bucket, path, only_directories=False, metadata=False):
        raise NotImplementedError(
            f"{self.__class__.__name__} has not implemented method '{inspect.currentframe().f_code.co_name}'"
        )

    def put_object(self, bucket, key, body, content_type=None, cache_control=None, metadata=None):
        raise NotImplementedError(
            f"{self.__class__.__name__} has not implemented method '{inspect.currentframe().f_code.co_name}'"
        )

    def check_object(self, bucket, key, retries=True):
        raise NotImplementedError(
            f"{self.__class__.__name__} has not implemented method '{inspect.currentframe().f_code.co_name}'"
        )

    def delete_object(self, bucket, key):
        raise NotImplementedError(
            f"{self.__class__.__name__} has not implemented method '{inspect.currentframe().f_code.co_name}'"
        )

    def delete_objects(self, bucket, keys):
        raise NotImplementedError(
            f"{self.__class__.__name__} has not implemented method '{inspect.currentframe().f_code.co_name}'"
        )

    def presigned_request(self, bucket, key, method, internal=True):
        raise NotImplementedError(
            f"{self.__class__.__name__} has not implemented method '{inspect.currentframe().f_code.co_name}'"
        )
