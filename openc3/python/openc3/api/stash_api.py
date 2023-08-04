# Copyright 2022 OpenC3, Inc
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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.:

import json
from openc3.api import WHITELIST
from openc3.environment import OPENC3_SCOPE
from openc3.utilities.authorization import authorize
from openc3.models.stash_model import StashModel

WHITELIST.extend(["stash_set", "stash_get", "stash_all", "stash_keys", "stash_delete"])


def stash_set(key, value, scope=OPENC3_SCOPE):
    authorize(permission="script_run", scope=scope)
    return StashModel.set(
        {"name": key, "value": json.dumps(value.as_json())}, scope=scope
    )


def stash_get(key, scope=OPENC3_SCOPE):
    authorize(permission="script_view", scope=scope)
    result = StashModel.get(name=key, scope=scope)
    if result:
        return json.loads(result["value"])
    else:
        return None


def stash_all(scope=OPENC3_SCOPE):
    authorize(permission="script_view", scope=scope)
    all = StashModel.all(scope=scope)
    for key, hash in all:
        all[key] = json.loads(hash["value"])
    return all


def stash_keys(scope=OPENC3_SCOPE):
    authorize(permission="script_view", scope=scope)
    return StashModel.names(scope=scope)


def stash_delete(key, scope=OPENC3_SCOPE):
    authorize(permission="script_run", scope=scope)
    model = StashModel.get_model(name=key, scope=scope)
    if model:
        model.destroy
    return model
