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

import os

from openc3.top_level import get_class_from_module
from openc3.utilities.string import filename_to_class_name


if os.getenv("OPENC3_SECRET_BACKEND") is None:
    os.environ["OPENC3_SECRET_BACKEND"] = "redis"


class Secrets:
    # Default base directory that FILE type secret paths must reside under.
    # FILE type secrets are written by the operator (or mounted by Kubernetes)
    # and then read back by the microservice, so the path is a destination we
    # control, not an arbitrary file on the host.
    DEFAULT_SECRET_FILE_DIR = "/tmp"

    def __init__(self):
        self.local_secrets = {}

    @classmethod
    def secret_file_dir(cls):
        """Base directory that FILE type secret paths must reside under"""
        return os.environ.get("OPENC3_SECRET_FILE_DIR") or cls.DEFAULT_SECRET_FILE_DIR

    @classmethod
    def validate_file_path(cls, path):
        """Validates a FILE type secret path. The path must expand to a location
        strictly inside secret_file_dir(). This prevents a plugin configuration such
        as 'SECRET FILE KEY /root/.ssh/id_rsa' or 'SECRET FILE KEY /tmp/../etc/shadow'
        from reading arbitrary files as the OpenC3 process user.

        Returns the validated absolute path.
        """
        if not isinstance(path, str):
            raise ValueError(f"Secret file path must be a str but is a {type(path).__name__}")
        if not path.strip():
            raise ValueError("Secret file path must not be blank")
        if "\x00" in path:
            raise ValueError("Secret file path must not contain a null byte")

        # abspath collapses '..' and '.' and makes a relative path absolute, so the
        # comparison below can't be walked out of. This is deliberately a purely
        # lexical check: it does not touch the filesystem, so a path validates
        # identically at plugin install time and at write time, which happen in
        # separate containers. Symlinks are rejected by the operator when it writes
        # the secret. expanduser matches Ruby's File.expand_path handling of '~'.
        base = os.path.abspath(os.path.expanduser(cls.secret_file_dir()))
        absolute = os.path.abspath(os.path.expanduser(path))
        if not absolute.startswith(base + os.sep):
            raise ValueError(f"Secret file path '{path}' must be under '{base}'")
        return absolute

    @classmethod
    def get_client(cls):
        if os.getenv("OPENC3_SECRET_BACKEND") is None:
            raise RuntimeError("OPENC3_SECRET_BACKEND environment variable is required")
        secrets_file = os.getenv("OPENC3_SECRET_BACKEND").lower() + "_secrets"
        klass = get_class_from_module(
            f"openc3.utilities.{secrets_file}",
            filename_to_class_name(secrets_file),
        )
        return klass()

    def keys(self, secret_store=None, scope=None):
        raise RuntimeError(f"{self.__class__.__name__} has not implemented method 'keys'")

    def get(self, key, secret_store=None, scope=None):
        return self.local_secrets[key]

    def set(self, key, value, secret_store=None, scope=None):
        raise RuntimeError(f"{self.__class__.__name__} has not implemented method 'set'")

    def delete(self, key, secret_store=None, scope=None):
        raise RuntimeError(f"{self.__class__.__name__} has not implemented method 'delete'")

    def setup(self, secrets):
        for secret in secrets:
            if len(secret) < 3:
                raise ValueError(f"Secret must have at least 3 items (type, key, data), got {len(secret)}")
            type, key, data, *extra = secret  # *extra would be secret_store, but we don't need that here
            match type:
                case "ENV":
                    self.local_secrets[key] = os.environ.get(data)
                case "FILE":
                    with open(self.validate_file_path(data)) as file:
                        self.local_secrets[key] = file.read()
                case _:
                    raise RuntimeError(f"Unknown secret type: {type}")
