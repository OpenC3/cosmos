# Copyright 2024 OpenC3, Inc.
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

import re
import time
from datetime import datetime, timezone
from openc3.utilities.extract import remove_quotes
import traceback


class SuiteResults:
    metadata = None
    context = None

    def __init__(self):
        self._report = None
        self.context = None
        self.start_time = None
        self.stop_time = None
        self.results = None
        self.settings = None
        self.metadata = None

    def start(
        self,
        test_type,
        test_suite_class,
        test_class=None,
        test_case=None,
        settings=None,
    ):
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

    # process_result can handle an array of OpenC3TestResult objects
    # or a single OpenC3TestResult object
    def process_result(self, results):
        # If we were passed an array we concat it to the results global
        if isinstance(results, list):
            self.results.append(results)
        # A single result is appended and then turned into an array
        else:
            self.results.append(results)
            results = [results]

        # Process all the results (may be just one)
        for result in results:
            self.puts(f"{result.group}:{result.script}:{result.result}")
            if result.message:
                for line in result.message.split("\n"):
                    if re.search(r"\x00-\x08\x0B-\x0C\x0E-\x1F\x7F-\xFF", line):
                        line = line.rstrip("\n")
                        line = remove_quotes(repr(line))
                    self._report.append("  " + line.strip())

            if result.exceptions:
                self._report.append("  Exceptions:")
                for _, error in enumerate(result.exceptions):
                    self._report.append("".join(traceback.format_exception(error)))

    def complete(self):
        self.stop_time = time.time()
        self.footer()

    def report(self):
        return "\n".join(self._report)

    def header(self):
        self._report.append("--- Script Report ---")
        if self.settings:
            self._report.append("")
            self._report.append("Settings:")
            for setting_name, setting_value in self.settings.items():
                self._report.append(f"{setting_name} = {setting_value}")

        self._report.append("")
        self._report.append("Results:")
        self.puts(f"Executing {self.context}")

    def footer(self):
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

    def write(self, string):
        # Can't use isoformat because it appends "+00:00" instead of "Z"
        self._report.append(datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ") + ": " + string)

    # Define a few aliases
    puts = write
    print = write
