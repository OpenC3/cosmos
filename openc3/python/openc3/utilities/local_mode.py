# encoding: ascii-8bit

# Copyright 2022 OpenC3, Inc.
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

from openc3.environment import OPENC3_LOCAL_MODE_PATH

class LocalMode:
    LOCAL_MODE_PATH = OPENC3_LOCAL_MODE_PATH or "/plugins"

    @classmethod
    def open_local_file(cls, path, scope):
        try:
          full_path = f"{cls.LOCAL_MODE_PATH}/{scope}/targets_modified/{path}"
          return open(full_path, 'rb')
        except:
            return None
