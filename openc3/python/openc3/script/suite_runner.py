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

from .suite import Suite, Group, ScriptStatus
from openc3.tools.test_runner.test import TestSuite, Test
from .suite_results import SuiteResults
from openc3.script.exceptions import StopScript
import inspect

class UnassignedSuite(Suite):
    """Placeholder for all Groups discovered without assigned Suites"""
    pass


class SuiteRunner:
    suites = []
    settings = {}
    suite_results = None

    @classmethod
    def execute(cls, result_string, suite_class, group_class=None, script=None):
        SuiteRunner.suite_results = SuiteResults()
        for suite in SuiteRunner.suites:
            if suite.__class__ == suite_class:
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
                break

    @classmethod
    def start(cls, suite_class, group_class=None, script=None):
        result = []
        for suite in cls.execute("", suite_class, group_class, script):
            if script:
                result = suite.run_script(group_class, script)
                SuiteRunner.suite_results.process_result(result)
                if (result.exceptions and SuiteRunner.settings["Abort After Error"]) or result.stopped:
                    raise StopScript
            elif group_class:
                for result in suite.run_group(group_class):
                    SuiteRunner.suite_results.process_result(result)
                    if result.stopped:
                        raise StopScript
            else:
                for result in suite.run():
                    SuiteRunner.suite_results.process_result(result)
                    if result.stopped:
                        raise StopScript

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
                    raise StopScript

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
                    raise StopScript

    # Build list of Suites and Groups
    @classmethod
    def build_suites(cls, from_module=None, from_globals=None):
        SuiteRunner.suites = []
        suites = {}
        groups = []

        if from_module:
            for attr_name in dir(from_module):
                object = getattr(from_module, attr_name)
                if not inspect.isclass(object):
                    continue

                # If we inherit from Suite
                if issubclass(object, Suite) and object != Suite and object != TestSuite:
                    SuiteRunner.suites.insert(0, object())

                # If we inherit from Group
                if issubclass(object, Group) and object != Group and object != Test:
                    groups.append(object)

        if from_globals:
            for object in from_globals.values():
                if not inspect.isclass(object):
                    continue

                # If we inherit from Suite
                if issubclass(object, Suite) and object != Suite and object != TestSuite:
                    SuiteRunner.suites.insert(0, object())

                # If we inherit from Group
                if issubclass(object, Group) and object != Group and object != Test:
                    groups.append(object)

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
                        # Make uniq!
                        temp = set(cur_suite["groups"][group_class.__name__]["scripts"])
                        cur_suite["groups"][group_class.__name__]["scripts"] = list(temp)
                        cur_suite["groups"][group_class.__name__]["scripts"].sort()
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
                            # Make uniq!
                            temp = set(cur_suite["groups"][group_class.__name__]["scripts"])
                            cur_suite["groups"][group_class.__name__]["scripts"] = list(temp)
                            cur_suite["groups"][group_class.__name__]["scripts"].sort()
                        else:
                            raise Exception(f"{group_class} does not have a {script} method defined.")

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
                            raise Exception(f"{group_class} does not have a setup method defined.")

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
                            raise Exception(f"{group_class} does not have a teardown method defined.")

            if not suite.name == "CustomSuite":
                suites[suite.name()] = cur_suite

        return suites
