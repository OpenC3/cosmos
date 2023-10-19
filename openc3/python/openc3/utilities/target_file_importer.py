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

import tempfile
import importlib
import sys
from openc3.utilities.bucket import Bucket
from openc3.utilities.target_file import TargetFile
from openc3.environment import OPENC3_SCOPE, OPENC3_CONFIG_BUCKET

# The last item in the sys.meta_path is the PathFinder
# PathFinder locates modules according to a path like structure
# which is what we're doing with target file imports
print(sys.meta_path)
_real_pathfinder = sys.meta_path[-1]


class MyLoader(importlib.abc.Loader):
    # Normally this method returns None and Python creates the module
    # However, we're explicitly creating the module and executing it
    # here based on the contents provided by the spec.loader_state.
    def create_module(self, spec):
        if spec.loader_state:
            file = tempfile.NamedTemporaryFile(mode="w+t", suffix=".py")
            file.write(spec.loader_state)
            file.seek(0)  # Rewind so the file is ready to read
            spec = importlib.util.spec_from_file_location(spec.name, file.name)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            file.close()
            return module
        return None

    # Normally this is where the module is executed and populated.
    # However, this let to some recursion issues so we do that above
    # in the create_module method.
    def exec_module(self, module):
        pass


class MyFinder(type(_real_pathfinder)):
    @classmethod
    def find_spec(cls, name, path, target=None):
        parts = name.split(".")
        # We're relying on the fact that COSMOS target names are always
        # capitalized and Python package names are (almost) always lowercase.
        if parts[0].upper() == parts[0]:
            spec = cls.find_target_file(name, path)
            if spec:
                return spec
        # Invoke the original Python PathFinder
        return _real_pathfinder.find_spec(name, path, target)

    @classmethod
    def find_target_file(cls, name, path):
        # Convert the import statement: import INST.lib.filename
        # into a path: INST/lib/filename
        path_name = name.replace(".", "/")
        # Bucket paths can not start with '/' and must end in '/'
        path = f"{OPENC3_SCOPE}/targets/{path_name}/"
        # We strip the last item off the path because in the final
        # case that is a filename and not a directory:
        # import INST.lib.filename means filename.py in the INST/lib directory
        path = "/".join(path.split("/")[0:-2])
        dirs, files = Bucket.getClient().list_files(OPENC3_CONFIG_BUCKET, path)
        if dirs or files:
            # Create a ModuleSpec using our loader
            spec = importlib.machinery.ModuleSpec(name, MyLoader(), origin=None)
            # Must set submodule_search_locations to indicate this is a package
            spec.submodule_search_locations = [name]
            spec.has_location = False

            # Try to read the filename based on the last bit of the path
            # NOTE: This handles the target_modified vs target directory
            body = TargetFile.body(OPENC3_SCOPE, f"{path_name}.py")
            if body is not None:
                # If a file was actually there we assign it to loader_state
                # so the loader can parse it into a real module
                spec.loader_state = body.decode()
            # Even if the file was not there we return the spec so the next
            # level of the path can be processed. For example, we must return
            # a valid spec on 'INST' so 'INST.lib' can be processed and so on.
            return spec
        # If nothing is there this is a bad location so return None
        return None


sys.meta_path[-1] = MyFinder
