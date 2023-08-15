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

import sys
import copy
import re
from io import StringIO
from openc3.script.exceptions import StopScript, SkipScript
import openc3.script


class Suite:
    """Base class for Script Runner suites. OpenC3 Suites inherit from Suite
    and can implement setup and teardown methods. Script groups are added via add_group(Group)
    and individual scripts added via add_script(Group, script_method)."""

    def scripts(self):
        if not self.scripts:
            self.scripts = {}
        return self.scripts

    def plans(self):
        if not self.plans:
            self.plans = []
        return self.plans

    ###########################################################################
    # START PUBLIC API
    ###########################################################################

    # Explictly avoid creating an initialize method which forces users to call super()

    # Add a group to the suite
    def add_group(self, group_class):
        self.scripts()
        self.plans()
        if not group_class.__class__ == type:
            group_class = globals()[group_class]
        if not self.scripts.get(group_class, None):
            self.scripts[group_class] = group_class()
        self.plans.append(["GROUP", group_class, None])

    # Add a script to the suite
    def add_script(self, group_class, script):
        self.scripts()
        self.plans()
        if not group_class.__class__ == type:
            group_class = globals()[group_class]
        if not self.scripts.get(group_class, None):
            self.scripts[group_class] = group_class()
        self.plans.append(["SCRIPT", group_class, script])

    # Add a group setup to the suite
    def add_group_setup(self, group_class):
        self.scripts()
        self.plans()
        if not group_class.__class__ == type:
            group_class = globals()[group_class]
        if not self.scripts.get(group_class, None):
            self.scripts[group_class] = group_class()
        self.plans.append(["GROUP_SETUP", group_class, None])

    # Add a group teardown to the suite
    def add_group_teardown(self, group_class):
        self.scripts()
        self.plans()
        if not group_class.__class__ == type:
            group_class = globals()[group_class]
        if not self.scripts.get(group_class, None):
            self.scripts[group_class] = group_class()
        self.plans.append(["GROUP_TEARDOWN", group_class, None])

    ###########################################################################
    # END PUBLIC API
    ###########################################################################

    def __eq__(self, other):
        return self.name == other.name

    # Name of the suite
    def name(self):
        if self.__class__ != Suite:
            return self.__class__.__name__
        else:
            return "UnassignedSuite"

    # Returns the number of scripts in the suite including setup and teardown methods
    def get_num_scripts(self):
        num_scripts = 0
        for type, group_class, _ in self.plans:
            if type == "GROUP":
                num_scripts += group_class.get_num_scripts()
            else:
                num_scripts += 1

        if hasattr(self, "setup"):
            num_scripts += 1
        if hasattr(self, "teardown"):
            num_scripts += 1
        return num_scripts

    # Run all the scripts
    def run(self):
        ScriptResult.suite = self.name()
        ScriptStatus.instance.total = self.get_num_scripts()
        results = []

        # Setup the suite
        result = self.run_setup(True)
        if result:
            results.append(result)
        yield result
        if result.stopped:
            raise StopScript

        # Run each script
        for type, group_class, script in self.plans():
            match type:
                case "GROUP":
                    results.append(self.run_group(group_class, True))
                case "SCRIPT":
                    result = self.run_script(group_class, script, True)
                    results.append(result)
                    yield result
                    if (
                        result.exceptions and group_class.abort_on_exception
                    ) or result.stopped:
                        raise StopScript
                case "GROUP_SETUP":
                    result = self.run_group_setup(group_class, True)
                    if result:
                        results.append(result)
                    yield result
                    if (
                        result.exceptions and group_class.abort_on_exception
                    ) or result.stopped:
                        raise StopScript

                case "GROUP_TEARDOWN":
                    result = self.run_group_teardown(group_class, True)
                    if result:
                        results.append(result)
                    yield result
                    if (
                        result.exceptions and group_class.abort_on_exception
                    ) or result.stopped:
                        raise StopScript

        # Teardown the suite
        result = self.run_teardown(True)
        if result:
            results.append(result)
        yield result
        if result.stopped:
            raise StopScript
        ScriptResult.suite = None
        return results

    # Run a specific group
    def run_group(self, group_class, internal=False):
        if not internal:
            ScriptResult.suite = self.name()

        # Determine if this group_class is in the plan and the number of scripts associated with this group_class
        in_plan = False
        num_scripts = 0
        for plan_type, plan_group_class, plan_script in self.plans():
            if plan_type == "GROUP" and group_class == plan_group_class:
                in_plan = True

            if (
                (plan_type == "GROUP_SETUP" and group_class == plan_group_class)
                or (plan_type == "GROUP_TEARDOWN" and group_class == plan_group_class)
                or (plan_script and group_class == plan_group_class)
            ):
                num_scripts += 1

        if in_plan:
            if not internal:
                ScriptStatus.instance.total = group_class.get_num_scripts()
            results = self.scripts[group_class].run()
        else:
            results = []
            if not internal:
                ScriptStatus.instance.total = num_scripts

            # Run each setup, teardown, or script associated with this group_class in the order
            # defined in the plan
            for plan_type, plan_group_class, plan_script in self.plans():
                if plan_group_class == group_class:
                    match plan_type:
                        case "SCRIPT":
                            result = self.run_script(
                                plan_group_class, plan_script, True
                            )
                            results.append(result)
                            yield result
                        case "GROUP_SETUP":
                            result = self.run_group_setup(plan_group_class, True)
                            if result:
                                results.append(result)
                            yield result

                        case "GROUP_TEARDOWN":
                            result = self.run_group_teardown(plan_group_class, True)
                            if result:
                                results.append(result)
                            yield result
        if not internal:
            ScriptResult.suite = None
        return results

    # Run a specific script
    def run_script(self, group_class, script, internal=False):
        if not internal:
            ScriptResult.suite = self.name()
        if not internal:
            ScriptStatus.instance.total = 1
        result = self.scripts[group_class].run_script(script)
        if not internal:
            ScriptResult.suite = None
        return result

    def run_setup(self, internal=False):
        if not internal:
            ScriptResult.suite = self.name()
        result = None
        if "setup" in self.__class__ and self.scripts.length > 0:
            if not internal:
                ScriptStatus.instance.total = 1
            ScriptStatus.instance.status = f"{self.__class__.__name__} : setup"
            result = self.scripts[self.scripts.keys[0]].run_method(self, "setup")

        if not internal:
            ScriptResult.suite = None
        return result

    def run_teardown(self, internal=False):
        if not internal:
            ScriptResult.suite = self.name()
        result = None
        if "teardown" in self.__class__ and self.scripts.length > 0:
            if not internal:
                ScriptStatus.instance.total = 1
            ScriptStatus.instance.status = f"{self.__class__} : teardown"
            result = self.scripts[self.scripts.keys[0]].run_method(self, "teardown")

        if not internal:
            ScriptResult.suite = None
        return result

    def run_group_setup(self, group_class, internal=False):
        if not internal:
            ScriptResult.suite = self.name()
        if not internal:
            ScriptStatus.instance.total = 1
        result = self.scripts[group_class].run_setup()
        if not internal:
            ScriptResult.suite = None
        return result

    def run_group_teardown(self, group_class, internal=False):
        if not internal:
            ScriptResult.suite = self.name()
        if not internal:
            ScriptStatus.instance.total = 1
        result = self.scripts[group_class].run_teardown()
        if not internal:
            ScriptResult.suite = None
        return result


class Group:
    """Base class for a group. All OpenC3 Script Runner scripts should inherit Group
    and then implement scripts methods starting with 'script_', 'test_', or 'op_'
    e.g. script_mech_open, test_mech_open, op_mech_open."""

    abort_on_exception = False
    current_result = None

    # Explictly avoid creating an initialize method which forces users to call super()

    @classmethod
    def scripts(cls):
        # Find all the script methods
        return [
            func
            for func in dir(cls)
            if callable(getattr(cls, func)) and re.search(r"^test|^script|op_", func)
        ].sort()

    # Name of the script group
    def name(self):
        if self.__class__ != Group:
            return self.__class__.__name__
        else:
            return "UnnamedGroup"

    # Run all the scripts
    def run(self):
        results = []

        # Setup the script group
        result = self.run_setup()
        if result:
            results.append(result)
        yield result
        if (results[-1].exceptions and Group.abort_on_exception) or results[-1].stopped:
            raise StopScript

        # Run all the scripts
        for method_name in self.__class__.scripts():
            results << self.run_script(method_name)
            yield results[-1]
            if (results[-1].exceptions and Group.abort_on_exception) or results[
                -1
            ].stopped:
                raise StopScript

        # Teardown the script group
        result = self.run_teardown()
        if result:
            results.append(result)
        yield result
        if (results[-1].exceptions and Group.abort_on_exception) or results[-1].stopped:
            raise StopScript
        return results

    # Run a specific script method
    def run_script(self, method_name):
        ScriptStatus.instance.status = f"{self.__class__.__name__} : {method_name}"
        self.run_method(self, method_name)

    def run_method(self, object, method_name):
        result = ScriptResult()
        Group.current_result = result

        # Verify script method exists
        if hasattr(object.__class__, method_name):
            self.output_io = self.output_io or StringIO("")
            # Capture STDOUT and STDERR
            sys.stdout.add_stream(self.output_io)
            sys.stderr.add_stream(self.output_io)

            result.group = object.__class__.__name__
            result.script = method_name
            try:
                object.public_send(method_name)
                result.result = "PASS"

                if (
                    openc3.script.RUNNING_SCRIPT.instance
                    and openc3.script.RUNNING_SCRIPT.instance.exceptions
                ):
                    result.exceptions = openc3.script.RUNNING_SCRIPT.instance.exceptions
                    result.result = "FAIL"
                    openc3.script.RUNNING_SCRIPT.instance.exceptions = None

            except Exception as error:
                # Check that the error belongs to the StopScript inheritance chain
                if issubclass(error, StopScript):
                    result.stopped = True
                    result.result = "STOP"
                # Check that the error belongs to the SkipScript inheritance chain
                elif issubclass(error, SkipScript):
                    result.result = "SKIP"
                    result.message = result.message or ""
                    result.message += error.message + "\n"
                else:
                    if (
                        not openc3.script.RUNNING_SCRIPT.instance
                        or not openc3.script.RUNNING_SCRIPT.instance.exceptions
                        or error not in openc3.script.RUNNING_SCRIPT.instance.exceptions
                    ):
                        result.exceptions = result.exceptions or []
                        result.exceptions.append(error)
                    if (
                        openc3.script.RUNNING_SCRIPT.instance
                        and openc3.script.RUNNING_SCRIPT.instance.exceptions
                    ):
                        result.exceptions = result.exceptions or []
                        result.exceptions.append(
                            openc3.script.RUNNING_SCRIPT.instance.exceptions
                        )
                        openc3.script.RUNNING_SCRIPT.instance.exceptions = None
                if result.exceptions:
                    result.result = "FAIL"
            finally:
                result.output = self.output_io.string
                self.output_io.string = ""
                sys.stdout.remove_stream(self.output_io)
                sys.stdout.remove_stream(self.output_io)

                match result.result:
                    case "FAIL":
                        ScriptStatus.instance.fail_count += 1
                    case "SKIP":
                        ScriptStatus.instance.skip_count += 1
                    case "PASS":
                        ScriptStatus.instance.pass_count += 1
        else:
            Group.current_result = None
            raise Exception(f"Unknown method {method_name} for {object.__class__}")
        Group.current_result = None
        return result

    def run_setup(self):
        if "setup" in self.__class__:
            ScriptStatus.instance.status = f"{self.__class__} : setup"
        return self.run_script("setup")

    def run_teardown(self):
        if "teardown" in self.__class__:
            ScriptStatus.instance.status = f"{self.__class__} : teardown"
        return self.run_script("teardown")

    @classmethod
    def get_num_scripts(cls):
        num_scripts = 0
        if "setup" in cls:
            num_scripts += 1
        if "teardown" in cls:
            num_scripts += 1
        num_scripts += len(cls.scripts())
        return num_scripts

    @classmethod
    def puts(cls, string):
        sys.stdout.print(string)
        if Group.current_result:
            Group.current_result.message = Group.current_result.message or ""
            Group.current_result.message += string.chomp
            Group.current_result.message += "\n"

    @classmethod
    def current_suite(cls):
        if Group.current_result:
            return Group.current_result.suite
        else:
            return None

    @classmethod
    def current_group(cls):
        if Group.current_result:
            return Group.current_result.group
        else:
            return None

    @classmethod
    def current_script(cls):
        if Group.current_result:
            return Group.current_result.script
        else:
            return None


# Helper class to collect information about the running scripts like pass / fail counts
class ScriptStatus:
    instance_obj = None

    def __init__(self):
        self.status = ""
        self.pass_count = 0
        self.skip_count = 0
        self.fail_count = 0
        self.total = 1

    def instance(cls):
        if ScriptStatus.instance_obj:
            return ScriptStatus.instance_obj
        ScriptStatus.instance_obj = cls.__init__()
        return ScriptStatus.instance_obj


# Helper class to collect script result information
class ScriptResult:
    suite = None

    def __init__(self):
        self.suite = None
        if ScriptResult.suite:
            self.suite = copy.deepcopy(ScriptResult.suite)
        self.group = None
        self.script = None
        self.output = None
        self.exceptions = None
        self.stopped = False
        self.result = "SKIP"
        self.message = None
