# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import unittest

import openc3.script
from openc3.script.exceptions import SkipScript, SkipScriptError, StopScript, StopScriptError


class TestDeprecatedExceptionAliases(unittest.TestCase):
    """The Error suffix was added when the Python exceptions were standardized.
    The old names are kept as aliases so existing user scripts which raise or
    catch them continue to work."""

    def test_the_old_names_are_the_new_classes(self):
        self.assertIs(StopScript, StopScriptError)
        self.assertIs(SkipScript, SkipScriptError)

    def test_the_old_names_catch_what_the_library_raises(self):
        with self.assertRaises(StopScript):
            raise StopScriptError
        with self.assertRaises(SkipScript):
            raise SkipScriptError

    def test_the_new_names_catch_what_user_scripts_raise(self):
        with self.assertRaises(StopScriptError):
            raise StopScript
        with self.assertRaises(SkipScriptError):
            raise SkipScript

    def test_the_old_names_are_available_to_scripts(self):
        # Scripts run with 'from openc3.script import *' so the aliases have to
        # survive the star import, which is how the INST2 demo suite uses them
        self.assertIs(openc3.script.StopScript, StopScriptError)
        self.assertIs(openc3.script.SkipScript, SkipScriptError)


if __name__ == "__main__":
    unittest.main()
