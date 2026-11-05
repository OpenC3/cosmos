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

"""Offline regression tests: python3 -m unittest discover -s scripts/tests."""

import io
import runpy
import sys
import tempfile
import unittest
from contextlib import redirect_stderr
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
HERITAGE = runpy.run_path(str(ROOT / "scripts/heritage/code_heritage.py"))
AUDIT = runpy.run_path(str(ROOT / "scripts/license_audit/license_audit.py"))


class HeritageTests(unittest.TestCase):
    def test_rebranding_matches_source_and_comments(self):
        old = b"module Cosmos\nCosmos.old_api()\n# Cosmos packet parser\n"
        new = b"module OpenC3\nOpenC3.old_api()\n# OpenC3 packet parser\n"
        normalize = HERITAGE["normalize"]
        self.assertEqual(normalize(old, True), normalize(new, True))
        self.assertNotIn("<<LICENSE>>", normalize(new, True))

    def test_changed_namespaced_calls_remain_different(self):
        normalize = HERITAGE["normalize"]
        self.assertNotEqual(normalize(b"OpenC3.old_api()\n", True), normalize(b"OpenC3.new_api()\n", True))

    def test_license_comments_still_match(self):
        normalize = HERITAGE["normalize"]
        for prefix in ("#", "//", "*", "<!--", "REM"):
            with self.subTest(prefix=prefix):
                old = f"{prefix} Copyright 2022 Ball Aerospace & Technologies Corp.\n".encode()
                new = f"{prefix} Copyright 2026 OpenC3, Inc.\n".encode()
                self.assertEqual(normalize(old, True), ["<<LICENSE>>"])
                self.assertEqual(normalize(old, True), normalize(new, True))


class LicenseTests(unittest.TestCase):
    def test_descriptions_do_not_hide_license_alternatives(self):
        for licenses, expected in [
            (["GNU General Public License v2 (GPLv2)", "MIT"], "permissive"),
            (["MIT", "GNU General Public License v2 (GPLv2)"], "permissive"),
            (["GNU General Public License v2 (GPLv2) OR MIT"], "permissive"),
            (["MIT (http://opensource.org/licenses/MIT) AND GPL-3.0-only"], "restricted"),
            (["BSD-3-Clause (BSD) AND GPL-3.0-only"], "restricted"),
            (["(MIT OR Apache-2.0) AND GPL-3.0-only"], "restricted"),
            (["MPL-2.0 AND (Apache-2.0 OR MIT)"], "weak-copyleft"),
            (["GPL-2.0-only WITH Classpath-exception-2.0"], "weak-copyleft"),
        ]:
            with self.subTest(licenses=licenses):
                self.assertEqual(AUDIT["classify"](licenses)[1], expected)

    def test_incomplete_expressions_are_unknown(self):
        for expression in ("MIT)", "MIT AND", "MIT OR", "MIT WITH", "(MIT", "MIT (license", "MIT (BSD OR GPL)"):
            with self.subTest(expression=expression):
                self.assertEqual(AUDIT["classify"]([expression])[1], "unknown")

    def test_nonregistry_dependencies_stop_the_audit(self):
        for identifier in (
            "external-package@https://example.invalid/package.tgz",
            "external-package@github:example/package#0123456789",
            "https://example.invalid/package.tgz",
            "external-package@file:../package.tgz",
        ):
            for have_yaml in (False, True):
                with (
                    self.subTest(identifier=identifier, have_yaml=have_yaml),
                    tempfile.TemporaryDirectory() as directory,
                ):
                    path = Path(directory) / "pnpm-lock.yaml"
                    path.write_text(f"lockfileVersion: '9.0'\npackages:\n  '{identifier}': {{}}\n")
                    # Exercise both the optional YAML loader and the dependency-free fallback.
                    yaml = (
                        SimpleNamespace(safe_load=lambda text, identifier=identifier: {"packages": {identifier: {}}})
                        if have_yaml
                        else None
                    )
                    with patch.dict(sys.modules, {"yaml": yaml}), self.assertRaises(AUDIT["AuditError"]):
                        AUDIT["parse_pnpm_lock"](path, "pnpm-lock.yaml")

    def test_nonregistry_dependency_returns_incomplete_audit_exit_code(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(sys.modules, {"yaml": None}):
            path = Path(directory) / "pnpm-lock.yaml"
            path.write_text("packages:\n  'external@https://example.invalid/package.tgz': {}\n")
            main = AUDIT["main"]
            errors = io.StringIO()
            with (
                patch.dict(main.__globals__, {"MANIFESTS": [(path.name, "js", "runtime", "fixture")]}),
                redirect_stderr(errors),
            ):
                self.assertEqual(main(["--repo-root", directory, "--no-cache"]), 2)
            self.assertIn("nonregistry package sources", errors.getvalue())

    def test_registry_dependencies_still_parse_without_yaml(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(sys.modules, {"yaml": None}):
            path = Path(directory) / "pnpm-lock.yaml"
            path.write_text(
                "lockfileVersion: '9.0'\npackages:\n  vue@3.5.0:\n    resolution: {integrity: example}\n"
                "  '@babel/core@7.0.0': {}\nsnapshots:\n  vue@3.5.0: {}\n"
            )
            packages = AUDIT["parse_pnpm_lock"](path, "pnpm-lock.yaml")
            self.assertEqual({(p.name, p.version) for p in packages}, {("vue", "3.5.0"), ("@babel/core", "7.0.0")})


if __name__ == "__main__":
    unittest.main()
