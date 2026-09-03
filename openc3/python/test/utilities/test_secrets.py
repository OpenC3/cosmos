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

    # NOTE: validate_file_path is deliberately lexical and does not resolve
    # symlinks, so that a path validates identically at plugin install time and at
    # write time, which happen in separate containers. The operator resolves
    # symlinks before writing a secret.
    def test_does_not_resolve_symlinks(self):
        link = f"/tmp/openc3_secrets_test_link_{os.getpid()}"
        if os.path.lexists(link):
            os.unlink(link)
        os.symlink("/etc/passwd", link)
        try:
            self.assertEqual(Secrets.validate_file_path(link), link)
        finally:
            os.unlink(link)

    def test_allows_a_not_yet_created_file_in_a_not_yet_created_directory(self):
        self.assertEqual(
            Secrets.validate_file_path("/tmp/openc3_secrets_test_no_such_dir/cert"),
            "/tmp/openc3_secrets_test_no_such_dir/cert",
        )

    def test_expands_tilde_and_rejects_it_when_outside_the_secret_file_dir(self):
        with self.assertRaisesRegex(ValueError, "must be under"):
            Secrets.validate_file_path("~/.ssh/id_rsa")

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
            self.assertEqual(Secrets.validate_file_path(f"{dir}/cert"), f"{dir}/cert")
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
