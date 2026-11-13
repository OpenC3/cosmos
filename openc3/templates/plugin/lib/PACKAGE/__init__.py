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

# Python code shared across this plugin lives in this package. COSMOS puts
# every installed plugin's lib/ on sys.path, so a module placed directly in
# lib/ can collide with another plugin's module of the same name. Keeping it
# under this uniquely named package avoids that. See README.md.
