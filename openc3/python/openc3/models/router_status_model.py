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

from openc3.models.interface_status_model import InterfaceStatusModel


# Stores the status about a router. All the functionality is handled
# in the InterfaceStatusModel, so we simply inherit it.
class RouterStatusModel(InterfaceStatusModel):
    pass
