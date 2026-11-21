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

import re
import time
import traceback
from datetime import datetime, timezone
from typing import TYPE_CHECKING, Any

from openc3.utilities.extract import remove_quotes


if TYPE_CHECKING:
    from .suite import ScriptResult


class SuiteResults:
    """Collect the results of a Suite run and build the text report."""

    metadata = None
    context = None

    def __init__(self) -> None:
        """Create an empty SuiteResults. Call `start` before processing results."""
        self._report: list[str] = []
        self.context = None
        self.start_time = None
        self.stop_time = None
        self.results: list[ScriptResult] = []
        self.settings = None
        self.metadata = None

    def start(
        self,
        test_type: str,
        test_suite_class: type,
        test_class: type | None = None,
        test_case: str | None = None,
        settings: dict[str, Any] | None = None,
    ) -> None:
        """Start a new report and write its header.

        Args:
            test_type: Description of the run appended to the context, e.g. "Manual Setup".
            test_suite_class: The Suite class being executed.
            test_class: The Group class being executed, or None to execute the whole Suite.
            test_case: The script method being executed, or None to execute the whole Group.
                Requires test_class.
            settings: Suite runner settings to list in the report header.
        """
        self.results = []
        self.start_time = time.time()
        self.settings = settings
        self._report = []

        if test_case:
            # Executing a script
            self.context = f"{test_suite_class.__name__}:{test_class.__name__}:{test_case} {test_type}"
        elif test_class:
            # Executing a group
            self.context = f"{test_suite_class.__name__}:{test_class.__name__} {test_type}"
        else:
            # Executing a suite
            self.context = f"{test_suite_class.__name__} {test_type}"
        self.header()

    def process_result(self, results: "ScriptResult | list[ScriptResult]") -> None:
        """Record one or more script results and add them to the report.

        Args:
            results: A single ScriptResult or a list of them.
        """
        # If we were passed an array we concat it to the results global
        if isinstance(results, list):
            self.results.extend(results)
        # A single result is appended and then turned into an array
        else:
            self.results.append(results)
            results = [results]

        # Process all the results (may be just one)
        for result in results:
            self.puts(f"{result.group}:{result.script}:{result.result}")
            if result.message:
                for line in result.message.split("\n"):
                    if re.search(r"[\x00-\x08\x0B-\x0C\x0E-\x1F\x7F-\xFF]", line):
                        line = line.rstrip("\n")
                        line = remove_quotes(repr(line))
                    self._report.append("  " + line.strip())

            if result.exceptions:
                self._report.append("  Exceptions:")
                for _, error in enumerate(result.exceptions):
                    self._report.append("".join(traceback.format_exception(error)))

    def complete(self) -> None:
        """Mark the run complete and write the report footer with the summary."""
        self.stop_time = time.time()
        self.footer()

    def report(self) -> str:
        """Return the report text.

        Returns:
            The report lines joined with newlines.
        """
        return "\n".join(self._report)

    def header(self) -> None:
        """Write the report header with the settings and the execution context."""
        self._report.append("--- Script Report ---")
        if self.settings:
            self._report.append("")
            self._report.append("Settings:")
            for setting_name, setting_value in self.settings.items():
                self._report.append(f"{setting_name} = {setting_value}")

        self._report.append("")
        self._report.append("Results:")
        self.puts(f"Executing {self.context}")

    def footer(self) -> None:
        """Write the report footer with the run time and the pass, skip and fail counts."""
        self.puts(f"Completed {self.context}")

        self._report.append("")
        self._report.append("--- Test Summary ---")
        self._report.append("")

        pass_count = 0
        skip_count = 0
        fail_count = 0
        stopped = False
        for result in self.results:
            if result.result == "PASS":
                pass_count += 1
            elif result.result == "SKIP":
                skip_count += 1
            elif result.result == "FAIL":
                fail_count += 1
            if result.stopped:
                stopped = True

        run_time = self.stop_time - self.start_time
        self._report.append(f"Run Time: {run_time}")
        self._report.append(f"Total Tests: {len(self.results)}")
        self._report.append(f"Pass: {pass_count}")
        self._report.append(f"Skip: {skip_count}")
        self._report.append(f"Fail: {fail_count}")
        self._report.append("")
        if stopped:
            self._report.append("*** Test was stopped prematurely ***")
            self._report.append("")

    def write(self, string: str) -> None:
        """Write a UTC timestamped line to the report.

        Args:
            string: The text to write.
        """
        # Can't use isoformat because it appends "+00:00" instead of "Z"
        self._report.append(datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ") + ": " + string)

    # Define a few aliases
    puts = write
    print = write
