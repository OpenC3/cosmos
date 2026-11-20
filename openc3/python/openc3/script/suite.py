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

import copy
import re
import sys
from collections.abc import Generator
from io import StringIO
from typing import Any

import openc3.script
from openc3.io.stderr import Stderr
from openc3.io.stdout import Stdout
from openc3.script.exceptions import SkipScriptError, StopScriptError


class Suite:
    """Base class for Script Runner suites.

    Subclass Suite to collect Groups into a suite that Script Runner can run as
    a whole, a group at a time, or a script at a time. Build the plan in
    ``__init__`` by calling `add_group`, `add_script`, `add_group_setup` and
    `add_group_teardown`; items run in the order they are added. Suite has no
    ``__init__`` of its own, so a subclass does not need to call
    ``super().__init__()``.

    A subclass may also define ``setup(self)`` and ``teardown(self)``. Neither
    is defined on Suite itself: Script Runner calls them, if present, before
    and after the suite runs and offers them as separately runnable items::

        class MySuite(Suite):
            def __init__(self):
                self.add_group(ExampleGroup)
                self.add_script(OtherGroup, "script_1")

            def setup(self):
                print("Suite setup")

            def teardown(self):
                print("Suite teardown")
    """

    def scripts(self) -> dict[type["Group"], "Group"]:
        """Return the Group instances used by this suite, keyed by Group class.

        Returns:
            A dict mapping each added Group subclass to its single instance.
        """
        if not hasattr(self, "_scripts"):
            self._scripts = {}
        return self._scripts

    def plans(self) -> list[list[Any]]:
        """Return the run plan built by the add_* methods.

        Returns:
            A list of ``[type, group_class, script]`` entries in run order,
            where type is GROUP, SCRIPT, GROUP_SETUP or GROUP_TEARDOWN and
            script is the script method name for SCRIPT entries, else None.
        """
        if not hasattr(self, "_plans"):
            self._plans = []
        return self._plans

    ###########################################################################
    # START PUBLIC API
    ###########################################################################

    # Explicitly avoid creating an initialize method which forces users to call super()

    def add_group(self, group_class: type["Group"]) -> None:
        """Add a group to the suite.

        Runs the group's setup, every script method and the group's teardown.

        Args:
            group_class: The Group subclass (the class, not an instance).

        Raises:
            RuntimeError: If group_class is not a subclass of Group.
        """
        if not issubclass(group_class, Group):
            raise RuntimeError(
                f"add_group received with {group_class}({group_class.__class__}) but must subclass Group"
            )
        if not self.scripts().get(group_class, None):
            self.scripts()[group_class] = group_class()
        self.plans().append(["GROUP", group_class, None])

    def add_script(self, group_class: type["Group"], script: str) -> None:
        """Add a single script method of a group to the suite.

        Args:
            group_class: The Group subclass (the class, not an instance).
            script: Name of the script method, e.g. "script_mech_open".

        Raises:
            RuntimeError: If group_class is not a subclass of Group.
        """
        if not issubclass(group_class, Group):
            raise RuntimeError(
                f"add_script received with {group_class}({group_class.__class__}) but must subclass Group"
            )
        if not self.scripts().get(group_class, None):
            self.scripts()[group_class] = group_class()
        self.plans().append(["SCRIPT", group_class, script])

    def add_group_setup(self, group_class: type["Group"]) -> None:
        """Add a group's setup method to the suite.

        Args:
            group_class: The Group subclass (the class, not an instance).

        Raises:
            RuntimeError: If group_class is not a subclass of Group.
        """
        if not issubclass(group_class, Group):
            raise RuntimeError(
                f"add_group_setup received with {group_class}({group_class.__class__}) but must subclass Group"
            )
        if not self.scripts().get(group_class, None):
            self.scripts()[group_class] = group_class()
        self.plans().append(["GROUP_SETUP", group_class, None])

    def add_group_teardown(self, group_class: type["Group"]) -> None:
        """Add a group's teardown method to the suite.

        Args:
            group_class: The Group subclass (the class, not an instance).

        Raises:
            RuntimeError: If group_class is not a subclass of Group.
        """
        if not issubclass(group_class, Group):
            raise RuntimeError(
                f"add_group_teardown received with {group_class}({group_class.__class__}) but must subclass Group"
            )
        if not self.scripts().get(group_class, None):
            self.scripts()[group_class] = group_class()
        self.plans().append(["GROUP_TEARDOWN", group_class, None])

    ###########################################################################
    # END PUBLIC API
    ###########################################################################

    def __eq__(self, other: Any) -> bool:
        """Compare suites by their name methods."""
        return self.name == other.name

    def name(self) -> str:
        """Return the name of the suite.

        Returns:
            The subclass name, or "UnassignedSuite" for a bare Suite.
        """
        if self.__class__ != Suite:
            return self.__class__.__name__
        else:
            return "UnassignedSuite"

    def get_num_scripts(self) -> int:
        """Return the number of scripts in the suite, including setup and teardown methods.

        Returns:
            The number of runnable items in the plan.
        """
        num_scripts = 0
        for type, group_class, _ in self.plans():
            if type == "GROUP":
                num_scripts += group_class.get_num_scripts()
            else:
                num_scripts += 1

        if hasattr(self, "setup"):
            num_scripts += 1
        if hasattr(self, "teardown"):
            num_scripts += 1
        return num_scripts

    def run(self) -> Generator["ScriptResult", None, list["ScriptResult"]]:
        """Run the suite setup, every item in the plan and the suite teardown.

        Yields:
            The ScriptResult of each setup, script and teardown as it completes.

        Returns:
            All of the ScriptResults, as the generator's return value.

        Raises:
            StopScriptError: If a script was stopped, or raised an exception
                while abort on exception is enabled.
        """
        ScriptResult.suite = self.name()
        ScriptStatus.instance().total = self.get_num_scripts()
        results = []

        # Setup the suite
        result = self.run_setup(True)
        if result:
            results.append(result)
            yield result
            if result.stopped:
                raise StopScriptError

        # Run each script
        for type, group_class, script in self.plans():
            match type:
                case "GROUP":
                    for result in self.run_group(group_class, True):
                        results.append(result)
                        yield result
                        if result.stopped:
                            raise StopScriptError
                case "SCRIPT":
                    result = self.run_script(group_class, script, True)
                    results.append(result)
                    yield result
                    if (result.exceptions and group_class.abort_on_exception) or result.stopped:
                        raise StopScriptError
                case "GROUP_SETUP":
                    result = self.run_group_setup(group_class, True)
                    if result:
                        results.append(result)
                        yield result
                        if (result.exceptions and group_class.abort_on_exception) or result.stopped:
                            raise StopScriptError

                case "GROUP_TEARDOWN":
                    result = self.run_group_teardown(group_class, True)
                    if result:
                        results.append(result)
                        yield result
                        if (result.exceptions and group_class.abort_on_exception) or result.stopped:
                            raise StopScriptError

        # Teardown the suite
        result = self.run_teardown(True)
        if result:
            results.append(result)
            yield result
            if result.stopped:
                raise StopScriptError
        ScriptResult.suite = None
        return results

    def run_group(
        self, group_class: type["Group"], internal: bool = False
    ) -> Generator["ScriptResult", None, list["ScriptResult"]]:
        """Run a single group of the suite.

        If the whole group was added with `add_group` the entire group runs.
        Otherwise only the setup, teardown and scripts of the group that were
        added individually run, in plan order.

        Args:
            group_class: The Group subclass to run.
            internal: True when called from `run`, which manages the suite
                name and total script count itself.

        Yields:
            The ScriptResult of each setup, script and teardown as it completes.

        Returns:
            All of the ScriptResults, as the generator's return value.

        Raises:
            StopScriptError: If a script of a fully added group was stopped.
        """
        results = []
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
                ScriptStatus.instance().total = group_class.get_num_scripts()
            for result in self.scripts()[group_class].run():
                results.append(result)
                yield result
                if result.stopped:
                    raise StopScriptError
        else:
            if not internal:
                ScriptStatus.instance().total = num_scripts

            # Run each setup, teardown, or script associated with this group_class in the order
            # defined in the plan
            for plan_type, plan_group_class, plan_script in self.plans():
                if plan_group_class == group_class:
                    match plan_type:
                        case "SCRIPT":
                            result = self.run_script(plan_group_class, plan_script, True)
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

    def run_script(self, group_class: type["Group"], script: str, internal: bool = False) -> "ScriptResult":
        """Run a single script method of a group in the suite.

        Args:
            group_class: The Group subclass which defines the script.
            script: Name of the script method to run.
            internal: True when called from `run` or `run_group`.

        Returns:
            The result of the script.
        """
        if not internal:
            ScriptResult.suite = self.name()
        if not internal:
            ScriptStatus.instance().total = 1
        result = self.scripts()[group_class].run_script(script)
        if not internal:
            ScriptResult.suite = None
        return result

    def run_setup(self, internal: bool = False) -> "ScriptResult | None":
        """Run the suite's setup method, if the subclass defines one.

        Args:
            internal: True when called from `run`.

        Returns:
            The result of setup, or None if there is no setup or the suite has
            no groups.
        """
        if not internal:
            ScriptResult.suite = self.name()
        result = None
        if "setup" in dir(self) and len(self.scripts()) > 0:
            if not internal:
                ScriptStatus.instance().total = 1
            ScriptStatus.instance().status = f"{self.__class__.__name__} : setup"
            # Get the first group
            result = next(iter(self.scripts().values())).run_method(self, "setup")

        if not internal:
            ScriptResult.suite = None
        return result

    def run_teardown(self, internal: bool = False) -> "ScriptResult | None":
        """Run the suite's teardown method, if the subclass defines one.

        Args:
            internal: True when called from `run`.

        Returns:
            The result of teardown, or None if there is no teardown or the
            suite has no groups.
        """
        if not internal:
            ScriptResult.suite = self.name()
        result = None
        if "teardown" in dir(self) and len(self.scripts()) > 0:
            if not internal:
                ScriptStatus.instance().total = 1
            ScriptStatus.instance().status = f"{self.__class__} : teardown"
            # Get the first group
            result = next(iter(self.scripts().values())).run_method(self, "teardown")

        if not internal:
            ScriptResult.suite = None
        return result

    def run_group_setup(self, group_class: type["Group"], internal: bool = False) -> "ScriptResult | None":
        """Run a group's setup method.

        Args:
            group_class: The Group subclass whose setup runs.
            internal: True when called from `run` or `run_group`.

        Returns:
            The result of setup, or None if the group has no setup.
        """
        if not internal:
            ScriptResult.suite = self.name()
        if not internal:
            ScriptStatus.instance().total = 1
        result = self.scripts()[group_class].run_setup()
        if not internal:
            ScriptResult.suite = None
        return result

    def run_group_teardown(self, group_class: type["Group"], internal: bool = False) -> "ScriptResult | None":
        """Run a group's teardown method.

        Args:
            group_class: The Group subclass whose teardown runs.
            internal: True when called from `run` or `run_group`.

        Returns:
            The result of teardown, or None if the group has no teardown.
        """
        if not internal:
            ScriptResult.suite = self.name()
        if not internal:
            ScriptStatus.instance().total = 1
        result = self.scripts()[group_class].run_teardown()
        if not internal:
            ScriptResult.suite = None
        return result


class Group:
    """Base class for a group of Script Runner scripts.

    Subclass Group and define script methods whose names start with
    ``script_``, ``test_`` or ``op_``, e.g. ``script_mech_open``,
    ``test_mech_open`` or ``op_mech_open``. Script methods take no arguments
    besides self and run in alphabetical order. Group has no ``__init__`` of
    its own, so a subclass does not need to call ``super().__init__()``.

    A subclass may also define ``setup(self)`` and ``teardown(self)``, which
    run before the first and after the last script method when the whole group
    runs, and can be run on their own from Script Runner::

        class ExampleGroup(Group):
            def setup(self):
                print("Group setup")

            def script_1(self):
                Group.print("Step 1")

            def teardown(self):
                print("Group teardown")

    Raise SkipScriptError in a script method to mark it SKIP, and
    StopScriptError to stop the run. Any other exception marks it FAIL.

    Attributes:
        abort_on_exception: Stop the run after a script raises an exception.
            Script Runner sets this on Group from its "Abort After Error" option.
        current_result: The ScriptResult of the method that is running, or None.
    """

    abort_on_exception = False
    current_result = None

    # Explicitly avoid creating an initialize method which forces users to call super()

    @classmethod
    def scripts(cls) -> list[str]:
        """Return the names of the group's script methods.

        Returns:
            The sorted names of the methods starting with ``test_``,
            ``script_`` or ``op_``.
        """
        # Find all the script methods
        result = [
            func
            for func in dir(cls)
            if callable(getattr(cls, func))
            and re.search(r"^test_|^script_|^op_", func)
            and func != "scripts"
            and func != "test_cases"
        ]
        result.sort()
        return result

    def name(self) -> str:
        """Return the name of the group.

        Returns:
            The subclass name, or "UnnamedGroup" for a bare Group.
        """
        if self.__class__ != Group:
            return self.__class__.__name__
        else:
            return "UnnamedGroup"

    def run(self) -> Generator["ScriptResult", None, list["ScriptResult"]]:
        """Run the group setup, every script method and the group teardown.

        Yields:
            The ScriptResult of each setup, script and teardown as it completes.

        Returns:
            All of the ScriptResults, as the generator's return value.

        Raises:
            StopScriptError: If a script was stopped, or raised an exception
                while abort on exception is enabled.
        """
        results = []

        # Setup the script group
        result = self.run_setup()
        if result:
            results.append(result)
            yield result
            if (results[-1].exceptions and Group.abort_on_exception) or results[-1].stopped:
                raise StopScriptError

        # Run all the scripts
        for method_name in self.__class__.scripts():
            results.append(self.run_script(method_name))
            yield results[-1]
            if (results[-1].exceptions and Group.abort_on_exception) or results[-1].stopped:
                raise StopScriptError

        # Teardown the script group
        result = self.run_teardown()
        if result:
            results.append(result)
            yield result
            if (results[-1].exceptions and Group.abort_on_exception) or results[-1].stopped:
                raise StopScriptError
        return results

    def run_script(self, method_name: str) -> "ScriptResult":
        """Run a single method of the group.

        Args:
            method_name: Name of the method to run, e.g. "script_1" or "setup".

        Returns:
            The result of the method.
        """
        ScriptStatus.instance().status = f"{self.__class__.__name__} : {method_name}"
        return self.run_method(self, method_name)

    def run_method(self, object: Any, method_name: str) -> "ScriptResult":
        """Run a method of an object and capture its output and outcome.

        Stdout and stderr are captured into the result while the method runs,
        and the pass, skip or fail count of ScriptStatus is incremented.

        Args:
            object: The Group or Suite instance which defines the method.
            method_name: Name of the method to run.

        Returns:
            The result of the method: PASS, SKIP, FAIL or STOP.

        Raises:
            Exception: If the object's class does not define method_name.
        """
        result = ScriptResult()
        Group.current_result = result

        # Verify script method exists
        if hasattr(object.__class__, method_name):
            if hasattr(self, "output_io"):
                self.output_io = self.output_io or StringIO("")
            else:
                self.output_io = StringIO("")

            # Capture STDOUT and STDERR
            sys.stdout = Stdout.instance()
            sys.stderr = Stderr.instance()
            sys.stdout.add_stream(self.output_io)
            sys.stderr.add_stream(self.output_io)

            result.group = object.__class__.__name__
            result.script = method_name
            try:
                method = getattr(object, method_name)
                method()
                result.result = "PASS"

                if openc3.script.RUNNING_SCRIPT and openc3.script.RUNNING_SCRIPT.instance.exceptions:
                    result.exceptions = openc3.script.RUNNING_SCRIPT.instance.exceptions
                    result.result = "FAIL"
                    openc3.script.RUNNING_SCRIPT.instance.exceptions = None

            except Exception as error:
                if isinstance(error, StopScriptError):
                    result.stopped = True
                    result.result = "STOP"
                if isinstance(error, SkipScriptError):
                    result.result = "SKIP"
                    if hasattr(error, "message"):
                        result.message = result.message or ""
                        result.message += error.message + "\n"
                else:
                    if not isinstance(error, StopScriptError) and (
                        not openc3.script.RUNNING_SCRIPT
                        or not openc3.script.RUNNING_SCRIPT.instance
                        or not openc3.script.RUNNING_SCRIPT.instance.exceptions
                        or error not in openc3.script.RUNNING_SCRIPT.instance.exceptions
                    ):
                        result.exceptions = result.exceptions or []
                        result.exceptions.append(error)
                    if (
                        openc3.script.RUNNING_SCRIPT
                        and openc3.script.RUNNING_SCRIPT.instance
                        and openc3.script.RUNNING_SCRIPT.instance.exceptions
                    ):
                        result.exceptions = result.exceptions or []
                        result.exceptions.extend(openc3.script.RUNNING_SCRIPT.instance.exceptions)
                        openc3.script.RUNNING_SCRIPT.instance.exceptions = None
                if result.exceptions:
                    result.result = "FAIL"
            finally:
                result.output = self.output_io.getvalue()
                self.output_io.truncate(0)
                self.output_io.seek(0)
                sys.stdout.remove_stream(self.output_io)
                sys.stdout.remove_stream(self.output_io)

                match result.result:
                    case "FAIL":
                        ScriptStatus.instance().fail_count += 1
                    case "SKIP":
                        ScriptStatus.instance().skip_count += 1
                    case "PASS":
                        ScriptStatus.instance().pass_count += 1
        else:
            Group.current_result = None
            raise Exception(f"Unknown method {method_name} for {object.__class__}")
        Group.current_result = None
        return result

    def run_setup(self) -> "ScriptResult | None":
        """Run the group's setup method, if the subclass defines one.

        Returns:
            The result of setup, or None if there is no setup.
        """
        result = None
        if "setup" in dir(self):
            ScriptStatus.instance().status = f"{self.__class__} : setup"
            result = self.run_script("setup")
        return result

    def run_teardown(self) -> "ScriptResult | None":
        """Run the group's teardown method, if the subclass defines one.

        Returns:
            The result of teardown, or None if there is no teardown.
        """
        result = None
        if "teardown" in dir(self):
            ScriptStatus.instance().status = f"{self.__class__} : teardown"
            result = self.run_script("teardown")
        return result

    @classmethod
    def get_num_scripts(cls) -> int:
        """Return the number of scripts in the group, including setup and teardown methods.

        Returns:
            The number of script methods, plus one each for setup and teardown.
        """
        num_scripts = 0
        if "setup" in dir(cls):
            num_scripts += 1
        if "teardown" in dir(cls):
            num_scripts += 1
        num_scripts += len(cls.scripts())
        return num_scripts

    @classmethod
    def puts(cls, string: str) -> None:
        """Print a line and add it to the message of the running script's result.

        Args:
            string: The text to print.
        """
        print(string, file=sys.stdout)
        if Group.current_result:
            Group.current_result.message = Group.current_result.message or ""
            Group.current_result.message += string.rstrip("\n")
            Group.current_result.message += "\n"

    @classmethod
    def print(cls, string: str) -> None:
        """Print a line and add it to the message of the running script's result.

        Args:
            string: The text to print.
        """
        print(string, file=sys.stdout)
        if Group.current_result:
            Group.current_result.message = Group.current_result.message or ""
            Group.current_result.message += string.rstrip("\n")
            Group.current_result.message += "\n"

    @classmethod
    def current_suite(cls) -> str | None:
        """Return the name of the suite that is running.

        Returns:
            The suite name, or None if no script is running.
        """
        if Group.current_result:
            return Group.current_result.suite
        else:
            return None

    @classmethod
    def current_group(cls) -> str | None:
        """Return the name of the group that is running.

        Returns:
            The group name, or None if no script is running.
        """
        if Group.current_result:
            return Group.current_result.group
        else:
            return None

    @classmethod
    def current_script(cls) -> str | None:
        """Return the name of the script method that is running.

        Returns:
            The script method name, or None if no script is running.
        """
        if Group.current_result:
            return Group.current_result.script
        else:
            return None


# Helper class to collect information about the running scripts like pass / fail counts
class ScriptStatus:
    """Singleton holding the status and pass / skip / fail counts of the running scripts.

    Attributes:
        status: Description of the item that is running, e.g. "MyGroup : script_1".
        pass_count: Number of scripts which passed.
        skip_count: Number of scripts which were skipped.
        fail_count: Number of scripts which failed.
        total: Number of scripts in the current run.
    """

    instance_obj = None

    def __init__(self) -> None:
        """Initialize empty status and zero counts."""
        self.status = ""
        self.pass_count = 0
        self.skip_count = 0
        self.fail_count = 0
        self.total = 1

    @classmethod
    def instance(cls) -> "ScriptStatus":
        """Return the singleton instance, creating it on first use.

        Returns:
            The ScriptStatus instance.
        """
        if ScriptStatus.instance_obj:
            return ScriptStatus.instance_obj
        ScriptStatus.instance_obj = cls()
        return ScriptStatus.instance_obj


# Helper class to collect script result information
class ScriptResult:
    """Result of running one suite, group or script method.

    Attributes:
        suite: Name of the suite, or None.
        group: Name of the class which defines the method.
        script: Name of the method.
        output: Captured stdout and stderr of the method.
        exceptions: Exceptions raised by the method, or None.
        stopped: True if the method raised StopScriptError.
        result: PASS, SKIP (the default), FAIL or STOP.
        message: Text added by SkipScriptError messages and Group.print, or None.
    """

    suite = None

    def __init__(self) -> None:
        """Initialize an empty result which defaults to SKIP."""
        self.suite = None
        if ScriptResult.suite:
            ScriptResult.suite = copy.deepcopy(ScriptResult.suite)
        self.group = None
        self.script = None
        self.output = None
        self.exceptions = None
        self.stopped = False
        self.result = "SKIP"
        self.message = None
