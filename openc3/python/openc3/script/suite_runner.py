#!/usr/bin/env python3

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
from .suite_results import SuiteResults
from openc3.script.exceptions import StopScript


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
                        ScriptStatus.instance.fail_count > 0
                        and SuiteRunner.settings["Break Loop On Error"]
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
                if (result.exceptions and Group.abort_on_exception) or result.stopped:
                    raise StopScript
            elif group_class:
                for result in suite.run_group(group_class):
                    SuiteRunner.suite_results.process_result(result)
                    if result.stopped:
                        raise StopScript
            else:
                for result in suite.run:
                    SuiteRunner.suite_results.process_result(result)
                    if result.stopped:
                        raise StopScript

    @classmethod
    def setup(cls, suite_class, group_class=None):
        for suite in cls.execute("Manual Setup", suite_class, group_class):
            if group_class:
                result = suite.run_group_setup(group_class)
            else:
                result = suite.run_setup

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
                result = suite.run_teardown

            if result:
                SuiteRunner.suite_results.process_result(result)
                if result.stopped:
                    raise StopScript

    # # Convert the OpenStruct structure to a simple hash
    # # TODO: Maybe just use hashes right from the beginning?
    # def self.open_struct_to_hash(object)
    #   hash = object.to_h
    #   hash.each do |key1, val1|
    #     if val1.is_a?(Hash)
    #       val1.each do |key2, val2|
    #         if val2.is_a?(OpenStruct)
    #           hash[key1][key2] = val2.to_h

    #   hash

    # Build list of Suites and Groups
    @classmethod
    def build_suites(cls):
        SuiteRunner.suites = []
        suites = {}
        groups = []
        # TODO: This is only the current namespace where Ruby was everything
        # How do we get all the objects?
        for object in globals():
            # If we inherit from Suite
            if isinstance(object, Suite):
                # Ensure they didn't override name for some reason
                if hasattr(object, "name"):
                    raise AttributeError(
                        f"{object} redefined the 'name' method. Delete the 'name' method and try again."
                    )

                # ObjectSpace.each_object appears to yield objects in the reverse
                # order that they were parsed by the interpreter so push each
                # Suite object to the front of the array to order as encountered
                SuiteRunner.suites.insert(0, object())

            # If we inherit from Group
            if isinstance(object, Group):
                # Ensure they didn't override self.name for some reason
                if hasattr(object, "name"):
                    raise AttributeError(
                        f"{object} redefined the 'self.name' method. Delete the 'self.name' method and try again."
                    )
                groups << object

        # Raise error if no suites or groups
        if len(SuiteRunner.suites) == 0 or len(groups) == 0:
            return "No Suite or no Group classes found"

        # Remove assigned Groups from the array of groups
        for suite in SuiteRunner.suites:
            if suite.__class__ == UnassignedSuite:
                continue
            groups_to_delete = []
            for group in groups:
                if suite.scripts[group]:
                    groups_to_delete.append(group)
            for group in groups_to_delete:
                groups.delete(group)

        if len(groups) == 0:
            # If there are no unassigned group we simply remove the UnassignedSuite
            SuiteRunner.suites = [
                suite
                for suite in SuiteRunner.suites
                if suite.__class__ != UnassignedSuite
            ]
        else:
            # unassigned groups should be added to the UnassignedSuite
            unassigned_suite = [
                suite
                for suite in SuiteRunner.suites
                if suite.__class__ == UnassignedSuite
            ]
            for group in groups:
                unassigned_suite.add_group(group)

        for suite in SuiteRunner.suites:
            cur_suite = {"setup": False, "teardown": False, "groups": {}}
            if "setup" in suite.__class__:
                cur_suite.setup = True
            if "teardown" in suite.__class__:
                cur_suite.teardown = True

            for type, group_class, script in suite.plans():
                match type:
                    case "GROUP":
                        if not cur_suite.groups.get(group_class.name):
                            cur_suite.groups[group_class.name] = {
                                "setup": False,
                                "teardown": False,
                                "scripts": [],
                            }
                        cur_suite.groups[group_class.name].scripts.append(
                            group_class.scripts
                        )
                        # cur_suite.groups[group_class.name].scripts.uniq!
                        if "setup" in group_class:
                            cur_suite.groups[group_class.name].setup = True
                        if "teardown" in group_class:
                            cur_suite.groups[group_class.name].teardown = True
                    case "SCRIPT":
                        if not cur_suite.groups.get(group_class.name):
                            cur_suite.groups[group_class.name] = {
                                "setup": False,
                                "teardown": False,
                                "scripts": [],
                            }
                        # Explicitly check for this method and raise an error if it does not exist
                        if script in group_class:
                            cur_suite.groups[group_class.name].scripts.append(script)
                            # cur_suite.groups[group_class.name].scripts.uniq!
                        else:
                            raise Exception(
                                f"{group_class} does not have a {script} method defined."
                            )

                        if "setup" in group_class:
                            cur_suite.groups[group_class.name].setup = True
                        if "teardown" in group_class:
                            cur_suite.groups[group_class.name].teardown = True
                    case "GROUP_SETUP":
                        if not cur_suite.groups.get(group_class.name):
                            cur_suite.groups[group_class.name] = {
                                "setup": False,
                                "teardown": False,
                                "scripts": [],
                            }
                        # Explicitly check for the setup method and raise an error if it does not exist
                        if "setup" in group_class:
                            cur_suite.groups[group_class.name].setup = True
                        else:
                            raise Exception(
                                f"{group_class} does not have a setup method defined."
                            )

                    case "GROUP_TEARDOWN":
                        if not cur_suite.groups.get(group_class.name):
                            cur_suite.groups[group_class.name] = {
                                "setup": False,
                                "teardown": False,
                                "scripts": [],
                            }
                        # Explicitly check for the teardown method and raise an error if it does not exist
                        if "teardown" in group_class:
                            cur_suite.groups[group_class.name].teardown = True
                        else:
                            raise Exception(
                                f"{group_class} does not have a teardown method defined."
                            )

            if not suite.name == "CustomSuite":
                suites[suite.name] = cur_suite

        return suites
