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


class frange:
    def __init__(self, start, stop, step=None):
        self.start = float(start)
        self.stop = float(stop)
        if step is None:
            self.step = 1.0

        count = 0
        while True:
            temp = float(self.start + count * self.step)
            if self.step > 0 and temp >= self.stop:
                break
            elif self.step < 0 and temp <= self.stop:
                break
            yield temp
            count += 1
