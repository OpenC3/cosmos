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

import inspect

from openc3.script.exceptions import StopScriptError
from openc3.tools.test_runner.test import Test, TestSuite

from .suite import Group, ScriptStatus, Suite
from .suite_results import SuiteResults


class UnassignedSuite(Suite):
    """Placeholder for all Groups discovered without assigned Suites"""

    pass


class SuiteRunner:
    # Default suite_runner options shared by all callers so the values stay
    # consistent in one place.
    DEFAULT_METHOD = "start"
    DEFAULT_OPTIONS = ["continueAfterError"]

    suites = []
    settings = {}
    suite_results = None

    # Validate the suite_runner option combinations that don't require the
    # built suites. Shared by all callers so the contract lives in one place.
    # Suite/Group existence is checked in execute since it needs the suites.
    @classmethod
    def validate_options(cls, group=None, script=None):
        if script and not group:
            raise ValueError(f"Script {script} requires a Group")

    # Build the canonical, validated suite_runner dict from raw values, applying
    # defaults. Shared so the dict shape, defaults, and validation live in one
    # place (used by the running script when normalizing a received dict).
    @classmethod
    def build_options(cls, suite, group=None, script=None, method=None, options=None):
        cls.validate_options(group=group, script=script)
        suite_runner = {"suite": suite}
        if group:
            suite_runner["group"] = group
            if script:
                suite_runner["script"] = script
        # A script always runs via start, matching the GUI
        suite_runner["method"] = cls.DEFAULT_METHOD if script else (method or cls.DEFAULT_METHOD)
        suite_runner["options"] = options if options is not None else list(cls.DEFAULT_OPTIONS)
        return suite_runner

    @classmethod
    def execute(cls, result_string, suite_class, group_class=None, script=None):
        SuiteRunner.suite_results = SuiteResults()
        # Surface invalid suite / group / option combinations rather than
        # silently running nothing or failing with an opaque error. An
        # invalid script method raises later in Group.run_method.
        cls.validate_options(group=group_class, script=script)
        suite = next((s for s in SuiteRunner.suites if s.__class__ == suite_class), None)
        if not suite:
            raise ValueError(f"Suite {suite_class} not found")
        if group_class and group_class not in suite.scripts():
            raise ValueError(f"Group {group_class} not found in Suite {suite_class}")
        SuiteRunner.suite_results.start(
            result_string,
            suite_class,
            group_class,
            script,
            SuiteRunner.settings,
        )
        while True:
            yield (suite)
            if not SuiteRunner.settings["Loop"] or (
                ScriptStatus.instance().fail_count > 0 and SuiteRunner.settings["Break Loop On Error"]
            ):
                break

    @classmethod
    def start(cls, suite_class, group_class=None, script=None):
        result = []
        for suite in cls.execute("", suite_class, group_class, script):
            if script:
                result = suite.run_script(group_class, script)
                SuiteRunner.suite_results.process_result(result)
                if (result.exceptions and SuiteRunner.settings["Abort After Error"]) or result.stopped:
                    raise StopScriptError
            elif group_class:
                for result in suite.run_group(group_class):
                    SuiteRunner.suite_results.process_result(result)
                    if result.stopped:
                        raise StopScriptError
            else:
                for result in suite.run():
                    SuiteRunner.suite_results.process_result(result)
                    if result.stopped:
                        raise StopScriptError

    @classmethod
    def setup(cls, suite_class, group_class=None):
        for suite in cls.execute("Manual Setup", suite_class, group_class):
            if group_class:
                result = suite.run_group_setup(group_class)
            else:
                result = suite.run_setup()

            if result:
                SuiteRunner.suite_results.process_result(result)
                if result.stopped:
                    raise StopScriptError

    @classmethod
    def teardown(cls, suite_class, group_class=None):
        for suite in cls.execute("Manual Teardown", suite_class, group_class):
            if group_class:
                result = suite.run_group_teardown(group_class)
            else:
                result = suite.run_teardown()

            if result:
                SuiteRunner.suite_results.process_result(result)
                if result.stopped:
                    raise StopScriptError

    # Build list of Suites and Groups
    @classmethod
    def build_suites(cls, from_module=None, from_globals=None):
        SuiteRunner.suites = []
        suites = {}
        groups = []

        if from_module:
            for attr_name in dir(from_module):
                attribute = getattr(from_module, attr_name)
                if not inspect.isclass(attribute):
                    continue

                # If we inherit from Suite
                if issubclass(attribute, Suite) and attribute != Suite and attribute != TestSuite:
                    SuiteRunner.suites.insert(0, attribute())

                # If we inherit from Group
                if issubclass(attribute, Group) and attribute != Group and attribute != Test:
                    groups.append(attribute)

        if from_globals:
            for attribute in from_globals.values():
                if not inspect.isclass(attribute):
                    continue

                # If we inherit from Suite
                if issubclass(attribute, Suite) and attribute != Suite and attribute != TestSuite:
                    SuiteRunner.suites.insert(0, attribute())

                # If we inherit from Group
                if issubclass(attribute, Group) and attribute != Group and attribute != Test:
                    groups.append(attribute)

        # Raise error if no suites or groups
        if len(SuiteRunner.suites) == 0 or len(groups) == 0:
            return "No Suite or no Group classes found"

        # Remove assigned Groups from the array of groups
        for suite in SuiteRunner.suites:
            if suite.__class__ == UnassignedSuite:
                continue
            groups_to_delete = []
            for group in groups:
                if group in suite.scripts():
                    groups_to_delete.append(group)
            for group in groups_to_delete:
                groups.remove(group)

        if len(groups) == 0:
            # If there are no unassigned group we simply remove the UnassignedSuite
            SuiteRunner.suites = [suite for suite in SuiteRunner.suites if suite.__class__ != UnassignedSuite]
        else:
            # unassigned groups should be added to the UnassignedSuite
            unassigned_suite = UnassignedSuite()
            for group in groups:
                unassigned_suite.add_group(group)

        for suite in SuiteRunner.suites:
            cur_suite = {"setup": False, "teardown": False, "groups": {}}
            if "setup" in dir(suite):
                cur_suite["setup"] = True
            if "teardown" in dir(suite):
                cur_suite["teardown"] = True

            for type, group_class, script in suite.plans():
                match type:
                    case "GROUP":
                        if not cur_suite["groups"].get(group_class.__name__):
                            cur_suite["groups"][group_class.__name__] = {
                                "setup": False,
                                "teardown": False,
                                "scripts": [],
                            }
                        cur_suite["groups"][group_class.__name__]["scripts"].extend(group_class.scripts())
                        # Make uniq! while preserving order
                        cur_suite["groups"][group_class.__name__]["scripts"] = list(
                            dict.fromkeys(cur_suite["groups"][group_class.__name__]["scripts"])
                        )
                        if "setup" in dir(group_class):
                            cur_suite["groups"][group_class.__name__]["setup"] = True
                        if "teardown" in dir(group_class):
                            cur_suite["groups"][group_class.__name__]["teardown"] = True
                    case "SCRIPT":
                        if not cur_suite["groups"].get(group_class.__name__):
                            cur_suite["groups"][group_class.__name__] = {
                                "setup": False,
                                "teardown": False,
                                "scripts": [],
                            }
                        # Explicitly check for this method and raise an error if it does not exist
                        if script in dir(group_class):
                            cur_suite["groups"][group_class.__name__]["scripts"].append(script)
                            # Make uniq! while preserving order
                            cur_suite["groups"][group_class.__name__]["scripts"] = list(
                                dict.fromkeys(cur_suite["groups"][group_class.__name__]["scripts"])
                            )
                        else:
                            raise AttributeError(f"{group_class} does not have a {script} method defined.")

                        if "setup" in dir(group_class):
                            cur_suite["groups"][group_class.__name__]["setup"] = True
                        if "teardown" in dir(group_class):
                            cur_suite["groups"][group_class.__name__]["teardown"] = True
                    case "GROUP_SETUP":
                        if not cur_suite["groups"].get(group_class.__name__):
                            cur_suite["groups"][group_class.__name__] = {
                                "setup": False,
                                "teardown": False,
                                "scripts": [],
                            }
                        # Explicitly check for the setup method and raise an error if it does not exist
                        if "setup" in dir(group_class):
                            cur_suite["groups"][group_class.__name__]["setup"] = True
                        else:
                            raise AttributeError(f"{group_class} does not have a setup method defined.")

                    case "GROUP_TEARDOWN":
                        if not cur_suite["groups"].get(group_class.__name__):
                            cur_suite["groups"][group_class.__name__] = {
                                "setup": False,
                                "teardown": False,
                                "scripts": [],
                            }
                        # Explicitly check for the teardown method and raise an error if it does not exist
                        if "teardown" in dir(group_class):
                            cur_suite["groups"][group_class.__name__]["teardown"] = True
                        else:
                            raise AttributeError(f"{group_class} does not have a teardown method defined.")

            if suite.name != "CustomSuite":
                suites[suite.name()] = cur_suite

        return suites
