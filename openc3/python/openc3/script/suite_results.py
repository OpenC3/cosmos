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

import re
import time
from datetime import datetime
from openc3.utilities.extract import remove_quotes


class SuiteResults:
    metadata = None

    def __init__(self):
        self.report = None
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
        self.report = []

        if test_case:
            # Executing a single test case
            self.context = (
                f"{test_suite_class.name()}:{test_class.name()}:{test_case} {test_type}"
            )
        elif test_class:
            # Executing an entire test
            self.context = f"{test_suite_class.name()}:{test_class.name()} {test_type}"
        else:
            # Executing a test suite
            self.context = f"{test_suite_class.name()} {test_type}"
        self.header()

    # process_result can handle an array of OpenC3TestResult objects
    # or a single OpenC3TestResult object
    def process_result(self, results):
        # If we were passed an array we concat it to the results global
        if type(results) == list:
            self.results.append(results)
        # A single result is appended and then turned into an array
        else:
            self.results.append(results)
            results = [results]

        # Process all the results (may be just one)
        for result in results:
            self.puts(f"{result.group}:{result.script}:{result.result}")
            if result.message:
                for line in result.message:
                    if re.search(r"\x00-\x08\x0B-\x0C\x0E-\x1F\x7F-\xFF", line):
                        line = line.rstrip()
                        line = remove_quotes(line)
                    self.report += "  " + line.rstrip()

            if result.exceptions:
                self.report += "  Exceptions:"
                for index, error in enumerate(result.exceptions):
                    self.report += repr(error)
                    # for line in repr(error):
                    #   next if /in run_text/.match?(line)
                    #   next if /running_script.rb/.match?(line)
                    #   next if line&.match?(openc3_lib)

                    #   if /[\x00-\x08\x0B-\x0C\x0E-\x1F\x7F-\xFF]/.match?(line)
                    #     line.chomp!
                    #     line = line.inspect.remove_quotes

                    #   self.report += '    ' + line.rstrip()
                    # if index != (result.exceptions.length - 1):
                    #   self.report += ''

    def complete(self):
        self.stop_time = time.time()
        self.footer()

    def report(self):
        return "\n".join(self.report)

    def header(self):
        self.report += "--- Script Report ---"
        if self.settings:
            self.report += ""
            self.report += "Settings:"
            for setting_name, setting_value in self.settings:
                self.report += f"{setting_name} = {setting_value}"

        self.report += ""
        self.report += "Results:"
        self.puts(f"Executing {self.context}")

    def footer(self):
        self.puts(f"Completed {self.context}")

        self.report += ""
        self.report += "--- Test Summary ---"
        self.report += ""

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
        self.report += f"Run Time: {run_time}"
        self.report += f"Total Tests: {len(self.results)}"
        self.report += f"Pass: {pass_count}"
        self.report += f"Skip: {skip_count}"
        self.report += f"Fail: {fail_count}"
        self.report += ""
        if stopped:
            self.report += "*** Test was stopped prematurely ***"
            self.report += ""

    def write(self, string):
        self.report += datetime.now().isoformat(" ") + ": " + string

    def puts(self, string):
        self.report += datetime.now().isoformat(" ") + ": " + string
