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
import tempfile
import unittest

from openc3.utilities.secrets import Secrets


class TestSecrets(unittest.TestCase):
    def setUp(self):
        self.saved_dir = os.environ.pop("OPENC3_SECRET_FILE_DIR", None)

    def tearDown(self):
        if self.saved_dir is None:
            os.environ.pop("OPENC3_SECRET_FILE_DIR", None)
        else:
            os.environ["OPENC3_SECRET_FILE_DIR"] = self.saved_dir

    def test_secret_file_dir_defaults_to_tmp(self):
        self.assertEqual(Secrets.secret_file_dir(), "/tmp")

    def test_secret_file_dir_uses_env(self):
        os.environ["OPENC3_SECRET_FILE_DIR"] = "/var/secrets"
        self.assertEqual(Secrets.secret_file_dir(), "/var/secrets")

    def test_secret_file_dir_ignores_blank_env(self):
        os.environ["OPENC3_SECRET_FILE_DIR"] = ""
        self.assertEqual(Secrets.secret_file_dir(), "/tmp")

    def test_allows_paths_under_the_secret_file_dir(self):
        self.assertEqual(Secrets.validate_file_path("/tmp/DATA/cert"), "/tmp/DATA/cert")
        self.assertEqual(Secrets.validate_file_path("/tmp/INST/MQTT_KEY"), "/tmp/INST/MQTT_KEY")

    def test_normalizes_the_returned_path(self):
        self.assertEqual(Secrets.validate_file_path("/tmp/DATA/./sub/../cert"), "/tmp/DATA/cert")

    def test_rejects_absolute_paths_outside_the_secret_file_dir(self):
        for path in ["/root/.ssh/id_rsa", "/etc/shadow", "/etc/passwd", "/openc3/lib/openc3.rb"]:
            with self.assertRaisesRegex(ValueError, "must be under"):
                Secrets.validate_file_path(path)

    def test_rejects_traversal_out_of_the_secret_file_dir(self):
        for path in ["/tmp/../etc/passwd", "/tmp/a/../../etc/passwd", "/tmp/../../etc/passwd"]:
            with self.assertRaisesRegex(ValueError, "must be under"):
                Secrets.validate_file_path(path)

    def test_rejects_relative_paths(self):
        with self.assertRaisesRegex(ValueError, "must be under"):
            Secrets.validate_file_path("../../openc3-cosmos-cmd-tlm-api/config/secrets.yml")

    def test_rejects_the_secret_file_dir_itself(self):
        for path in ["/tmp", "/tmp/"]:
            with self.assertRaisesRegex(ValueError, "must be under"):
                Secrets.validate_file_path(path)

    def test_rejects_a_symlink_pointing_outside_the_secret_file_dir(self):
        link = f"/tmp/openc3_secrets_test_link_{os.getpid()}"
        if os.path.lexists(link):
            os.unlink(link)
        os.symlink("/etc/passwd", link)
        try:
            with self.assertRaisesRegex(ValueError, "must be under"):
                Secrets.validate_file_path(link)
        finally:
            os.unlink(link)

    def test_rejects_a_symlinked_directory_pointing_outside_the_secret_file_dir(self):
        link = f"/tmp/openc3_secrets_test_dir_{os.getpid()}"
        if os.path.lexists(link):
            os.unlink(link)
        os.symlink("/etc", link)
        try:
            with self.assertRaisesRegex(ValueError, "must be under"):
                Secrets.validate_file_path(f"{link}/passwd")
        finally:
            os.unlink(link)

    def test_rejects_a_dangling_symlink_pointing_outside_the_secret_file_dir(self):
        # The operator opens the path for writing, which follows a dangling
        # symlink and creates the file it points at
        link = f"/tmp/openc3_secrets_test_dangling_{os.getpid()}"
        if os.path.lexists(link):
            os.unlink(link)
        os.symlink("/etc/openc3_secrets_test_does_not_exist", link)
        try:
            with self.assertRaisesRegex(ValueError, "must be under"):
                Secrets.validate_file_path(link)
            with self.assertRaisesRegex(ValueError, "must be under"):
                Secrets.validate_file_path(f"{link}/cert")
        finally:
            os.unlink(link)

    def test_allows_a_not_yet_created_file_in_a_not_yet_created_directory(self):
        self.assertEqual(
            Secrets.validate_file_path("/tmp/openc3_secrets_test_no_such_dir/cert"),
            "/tmp/openc3_secrets_test_no_such_dir/cert",
        )

    def test_rejects_blank_non_str_and_null_byte_paths(self):
        with self.assertRaisesRegex(ValueError, "blank"):
            Secrets.validate_file_path("")
        with self.assertRaisesRegex(ValueError, "blank"):
            Secrets.validate_file_path("   ")
        with self.assertRaisesRegex(ValueError, "must be a str"):
            Secrets.validate_file_path(None)
        with self.assertRaisesRegex(ValueError, "null byte"):
            Secrets.validate_file_path("/tmp/cert\x00/etc/passwd")

    def test_honors_openc3_secret_file_dir(self):
        with tempfile.TemporaryDirectory() as dir:
            os.environ["OPENC3_SECRET_FILE_DIR"] = dir
            real = os.path.realpath(dir)
            self.assertEqual(Secrets.validate_file_path(f"{real}/cert"), f"{real}/cert")
            with self.assertRaisesRegex(ValueError, "must be under"):
                Secrets.validate_file_path("/tmp/DATA/cert")

    def test_setup_requires_at_least_3_items(self):
        with self.assertRaisesRegex(ValueError, "at least 3 items"):
            Secrets().setup([["ENV", "KEY"]])

    def test_setup_raises_on_unknown_types(self):
        with self.assertRaisesRegex(RuntimeError, "Unknown secret type"):
            Secrets().setup([["OTHER", "KEY", "DATA"]])

    def test_setup_reads_env_secrets(self):
        os.environ["OPENC3_SECRETS_TEST"] = "value"
        try:
            secrets = Secrets()
            secrets.setup([["ENV", "KEY", "OPENC3_SECRETS_TEST"]])
            self.assertEqual(secrets.get("KEY", scope="DEFAULT"), "value")
        finally:
            del os.environ["OPENC3_SECRETS_TEST"]

    def test_setup_reads_file_secrets_under_the_secret_file_dir(self):
        path = f"/tmp/openc3_secrets_test_{os.getpid()}"
        with open(path, "w") as file:
            file.write("secret value")
        try:
            secrets = Secrets()
            secrets.setup([["FILE", "KEY", path]])
            self.assertEqual(secrets.get("KEY", scope="DEFAULT"), "secret value")
        finally:
            os.unlink(path)

    def test_setup_does_not_read_file_secrets_outside_the_secret_file_dir(self):
        for path in ["/etc/passwd", "/tmp/../etc/passwd"]:
            with self.assertRaisesRegex(ValueError, "must be under"):
                Secrets().setup([["FILE", "KEY", path]])
