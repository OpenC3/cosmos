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

from openc3.script.suite import Suite, Group
from openc3.script.exceptions import SkipScript


# @deprecated Use SkipScript
class SkipTestCase(SkipScript):
    pass


# @deprecated Use Suite
class TestSuite(Suite):
    def __init__(self):
        super().__init__()
        self.tests = self.scripts
        self.add_test = self.add_group
        self.add_test_case = self.add_script
        self.add_test_setup = self.add_group_setup
        self.add_test_teardown = self.add_group_teardown
        self.run_test = self.run_group
        self.run_test_case = self.run_script
        self.get_num_test = self.get_num_scripts
        self.run_test_setup = self.run_group_setup
        self.run_test_teardown = self.run_group_teardown


# @deprecated Use Group
class Test(Group):
    def __init__(self):
        super().__init__()
        self.run_test_case = self.run_script

    # Alias methods
    test_cases = Group.scripts
    get_num_tests = Group.get_num_scripts
    current_test_suite = Group.current_suite
    current_test_group = Group.current_group
    current_test = Group.current_group
    current_test_case = Group.current_script
