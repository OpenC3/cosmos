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

import datetime
import json


class JsonEncoder(json.JSONEncoder):
    def default(self, o):
        if isinstance(o, datetime.datetime):
            return o.strftime("%Y-%m-%d %H:%M:%S.%f")
        if isinstance(o, bytes | bytearray):
            return {
                "json_class": "String",
                "raw": list(o),
            }
        return json.JSONEncoder.default(self, o)


class JsonDecoder(json.JSONDecoder):
    # Ruby's Float#as_json (openc3/io/json_rpc.rb) encodes non-finite floats as
    # {"json_class": "Float", "raw": "NaN"|"Infinity"|"-Infinity"} because bare
    # NaN/Infinity literals are not valid JSON. Python's json module writes those
    # bare literals instead and reads them back natively, so only the decode side
    # needs to understand both forms.
    RUBY_SPECIAL_FLOATS = {
        "NaN": float("nan"),
        "Infinity": float("inf"),
        "-Infinity": float("-inf"),
    }

    def __init__(self, *args, **kwargs):
        json.JSONDecoder.__init__(self, object_hook=self.object_hook, *args, **kwargs)  # noqa: B026

    def object_hook(self, dct):
        json_class = dct.get("json_class")
        if json_class == "String":
            return bytes(dct["raw"])
        if json_class == "Float":
            raw = dct.get("raw")
            if isinstance(raw, str) and raw in self.RUBY_SPECIAL_FLOATS:
                return self.RUBY_SPECIAL_FLOATS[raw]
        return dct
