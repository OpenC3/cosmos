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
import json
import os
import runpy
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr
from functools import partial
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SCANNER = runpy.run_path(str(ROOT / ".github/scripts/malicious_code_scan.py"))
HERITAGE = runpy.run_path(str(ROOT / "scripts/heritage/code_heritage.py"))
AUDIT = runpy.run_path(str(ROOT / "scripts/license_audit/license_audit.py"))
APPROVED = {"verdict": "approved", "summary": "Reviewed", "issues_fixed": [], "unresolved_concerns": []}


def run(*args, cwd, env=None):
    return subprocess.run(args, cwd=cwd, env=env, text=True, capture_output=True, check=True)


def git(repo, *args):
    return run("git", "-c", "core.quotePath=false", *args, cwd=repo).stdout.strip()


def init_repo(path):
    path.mkdir()
    git(path, "init", "-q")
    git(path, "config", "user.name", "Test fixture")
    git(path, "config", "user.email", "fixture@example.invalid")
    git(path, "config", "core.hooksPath", os.devnull)
    git(path, "config", "commit.gpgsign", "false")


def executable(path, source):
    path.write_text(f"#!{sys.executable}\n" + source, encoding="utf-8")
    path.chmod(0o755)


class ScannerTests(unittest.TestCase):
    def test_renames_check_both_paths(self):
        for old, new, rule, location in [
            ("notes.txt", "AGENTS.md", "protected-path", "AGENTS.md"),
            ("AGENTS.md", "notes.txt", "protected-path", "AGENTS.md"),
            ("notes.txt", "team\tfolder/AGENTS.md", "protected-path", "team\tfolder/AGENTS.md"),
            ("payload.dat", "payload.so", "executable-file", "payload.so"),
            ("notes.txt", "manual.txt", None, None),
        ]:
            with self.subTest(old=old, new=new), tempfile.TemporaryDirectory() as directory:
                repo = Path(directory) / "repo"
                init_repo(repo)
                (repo / old).write_text("Use the established coding style.\n" * 8)
                git(repo, "add", ".")
                git(repo, "commit", "-qm", "baseline")
                base = git(repo, "rev-parse", "HEAD")
                (repo / new).parent.mkdir(parents=True, exist_ok=True)
                (repo / old).rename(repo / new)
                git(repo, "add", "-A")
                git(repo, "commit", "-qm", "move notes")
                scan = SCANNER["deterministic_scan"]
                with patch.dict(scan.__globals__, {"git": partial(git, repo)}):
                    findings, _ = scan(base, "HEAD", "", "")
                if rule is None:
                    self.assertEqual(findings, [])
                else:
                    self.assertTrue(
                        any(f.rule == rule and f.path == location and f.severity == "block" for f in findings)
                    )


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


REVIEWER_STUB = """
import json, os, sys
from pathlib import Path

name = Path(sys.argv[0]).name
if name == 'codex' and sys.argv[1] == 'login':
    sys.stdin.read()
    sys.exit(0)
config = json.loads(Path(os.environ['REVIEW_FIXTURE']).read_text())[name]
if config.get('edit'):
    Path('seed.txt').write_text(name + ' edit\\n')
    Path('new.txt').write_text(name + ' new file\\n')
if name == 'claude':
    print(config['output'], end='')
else:
    Path(sys.argv[sys.argv.index('--output-last-message') + 1]).write_text(config['output'])
sys.exit(config.get('exit', 0))
"""


class ReviewLoopTests(unittest.TestCase):
    def check_loop(self, claude=None, codex=None, expected_status="error", expected_commits="0", expected_author=None):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            repo = work / "repo"
            init_repo(repo)
            (repo / "seed.txt").write_text("original\n")
            git(repo, "add", ".")
            git(repo, "commit", "-qm", "baseline")
            git(repo, "update-ref", "refs/remotes/origin/main", "HEAD")
            bin_dir = work / "bin"
            bin_dir.mkdir()
            for name in ("claude", "codex"):
                executable(bin_dir / name, REVIEWER_STUB)
            fixture = work / "reviewers.json"
            fixture.write_text(
                json.dumps(
                    {
                        "claude": claude
                        if claude is not None
                        else {
                            "output": json.dumps({"is_error": False, "structured_output": APPROVED}),
                        },
                        "codex": codex if codex is not None else {"output": json.dumps(APPROVED)},
                    }
                )
            )
            output = work / "step-output"
            env = dict(os.environ)
            env.update(
                PATH=str(bin_dir) + os.pathsep + env["PATH"],
                REVIEW_FIXTURE=str(fixture),
                BASE_REF="main",
                CLAUDE_API_KEY="fixture",
                CODEX_API_KEY="fixture",
                OUT_DIR=str(work / "out"),
                GITHUB_OUTPUT=str(output),
                MAX_TURNS="2",
            )
            run("bash", str(ROOT / ".github/scripts/ai_review_loop.sh"), cwd=repo, env=env)
            outputs = dict(line.split("=", 1) for line in output.read_text().splitlines())
            self.assertEqual(outputs, {"status": expected_status, "commits": expected_commits})
            expected_text = f"{expected_author} edit\n" if expected_author else "original\n"
            self.assertEqual((repo / "seed.txt").read_text(), expected_text)
            self.assertEqual((repo / "new.txt").exists(), expected_author is not None)
            self.assertEqual(git(repo, "status", "--porcelain"), "")

    def test_claude_crash_rolls_back_partial_edits(self):
        self.check_loop(claude={"exit": 42, "output": "", "edit": True})

    def test_claude_requires_structured_output(self):
        for raw in ("", "{", "{}", '{"result":"done"}', json.dumps({"is_error": True, "structured_output": APPROVED})):
            with self.subTest(raw=raw):
                self.check_loop(claude={"output": raw, "edit": True})

    def test_codex_crash_preserves_only_previous_successful_fixes(self):
        changed = dict(APPROVED, verdict="changes_made", issues_fixed=["seed.txt:1 - fixture fix"])
        self.check_loop(
            claude={"output": json.dumps({"is_error": False, "structured_output": changed}), "edit": True},
            codex={"exit": 42, "output": json.dumps(APPROVED), "edit": True},
            expected_commits="1",
            expected_author="claude",
        )

    def test_both_reviewers_require_valid_schema(self):
        for result in (
            None,
            {},
            dict(APPROVED, verdict="invalid"),
            dict(APPROVED, issues_fixed=[123]),
            dict(APPROVED, summary=None),
            dict(APPROVED, unresolved_concerns={}),
            dict(APPROVED, extra=True),
        ):
            for reviewer in ("claude", "codex"):
                with self.subTest(result=result, reviewer=reviewer):
                    raw = {"is_error": False, "structured_output": result} if reviewer == "claude" else result
                    self.check_loop(**{reviewer: {"output": json.dumps(raw), "edit": True}})

    def test_multiple_results_are_rejected(self):
        raw = json.dumps(APPROVED) + "\n" + json.dumps(APPROVED)
        self.check_loop(codex={"output": raw, "edit": True})

    def test_successful_reviews_converge(self):
        self.check_loop(expected_status="converged")

    def test_successful_fixes_converge(self):
        changed = dict(APPROVED, verdict="changes_made", issues_fixed=["seed.txt:1 - fixture fix"])
        self.check_loop(
            claude={"output": json.dumps({"is_error": False, "structured_output": changed}), "edit": True},
            expected_status="converged",
            expected_commits="1",
            expected_author="claude",
        )


GH_STUB = """
import json, os, subprocess, sys
from pathlib import Path

endpoint = sys.argv[2]
fixture = json.loads(Path(os.environ['GATE_FIXTURE']).read_text())
head = 'a' * 40
if endpoint == 'repos/example/repo/pulls/7':
    data = {'state':'open', 'head':{'repo':{'full_name':'example/repo'},'sha':head,'ref':'feature'},
            'base':{'ref':'main'}, 'draft':False, 'user':{'login':'author'}, 'labels':[]}
elif endpoint.endswith('/status'):
    data = {'statuses':[{'context':'security/malicious-code-scan','state':'success'}]}
elif '/actions/runs?' in endpoint:
    data = {'workflow_runs':[{'id':1,'name':'Python Lint','status':'completed','conclusion':'success'}]}
elif endpoint.endswith('/comments'):
    data = fixture['comments']
elif endpoint.endswith('/commits/' + head):
    data = {'commit':{'message':'human change'}}
else:
    sys.exit('Unexpected API call: ' + endpoint)
if '--jq' in sys.argv:
    result = subprocess.run(['jq','-r',sys.argv[sys.argv.index('--jq')+1]], input=json.dumps(data), text=True)
    sys.exit(result.returncode)
print(json.dumps(data))
"""


class ReviewGateTests(unittest.TestCase):
    def test_only_workflow_bot_summaries_skip_review(self):
        body = "<!-- ai-adversarial-review -->\n<!-- ai-review-sha: " + "a" * 40 + " -->"
        for login, user_type, comment_body, expected_skip in [
            ("contributor", "User", body, "false"),
            ("other[bot]", "Bot", body, "false"),
            ("github-actions[bot]", "User", body, "false"),
            ("github-actions[bot]", "Bot", "quoting " + body, "false"),
            ("github-actions[bot]", "Bot", body.replace("a" * 40, "b" * 40), "false"),
            ("github-actions[bot]", "Bot", body, "true"),
        ]:
            with (
                self.subTest(login=login, user_type=user_type, body=comment_body),
                tempfile.TemporaryDirectory() as directory,
            ):
                work = Path(directory)
                bin_dir = work / "bin"
                bin_dir.mkdir()
                executable(bin_dir / "gh", GH_STUB)
                fixture = work / "api.json"
                fixture.write_text(
                    json.dumps(
                        {
                            "comments": [
                                {"user": {"login": login, "type": user_type}, "body": comment_body},
                            ]
                        }
                    )
                )
                output = work / "step-output"
                env = dict(os.environ)
                env.update(
                    PATH=str(bin_dir) + os.pathsep + env["PATH"],
                    GATE_FIXTURE=str(fixture),
                    GITHUB_REPOSITORY="example/repo",
                    EVENT_NAME="workflow_run",
                    OUT_DIR=str(work / "out"),
                    PR_NUMBER="7",
                    HEAD_SHA="a" * 40,
                    FORCE="false",
                    GITHUB_OUTPUT=str(output),
                )
                run("bash", str(ROOT / ".github/scripts/ai_review_gate.sh"), cwd=work, env=env)
                outputs = dict(line.split("=", 1) for line in output.read_text().splitlines())
                self.assertEqual(outputs["skip"], expected_skip)


if __name__ == "__main__":
    unittest.main()
