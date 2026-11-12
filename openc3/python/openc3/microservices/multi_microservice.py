# Copyright 2026 OpenC3, Inc.
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

import importlib
import importlib.util
import os
import sys
import threading

import openc3
from openc3.microservices.microservice import Microservice
from openc3.models.microservice_model import MicroserviceModel
from openc3.system.system import System
from openc3.utilities.logger import Logger
from openc3.utilities.sleeper import Sleeper
from openc3.utilities.store import EphemeralStore, Store
from openc3.utilities.string import filename_to_class_name
from openc3.utilities.thread_manager import ThreadManager


class MultiMicroservice(Microservice):
    """Runs other Python microservices as threads in one process, like
    multi_microservice.rb. They are given on the command line, or if none are
    given (as for a MICROSERVICE_GROUP's PYMULTIGROUP) they are the
    microservices that name this one as their parent."""

    def __init__(self, *args):
        super().__init__(*args)
        self.sleeper = Sleeper()

    def child_models(self):
        names = sys.argv[1:]
        if not names:
            names = sorted(
                name
                for name, config in MicroserviceModel.all(scope=self.scope).items()
                if config.get("parent") == self.name
            )
        models = []
        for name in names:
            model = MicroserviceModel.get_model(name=name, scope=self.scope)
            if model is not None and model.enabled:
                models.append(model)
        return models

    @staticmethod
    def load_class(model):
        filename = next((item for item in model.cmd if item.endswith(".py")), None)
        if filename is None:
            raise RuntimeError(f"Could not determine class filename from '{' '.join(model.cmd)}'")
        path = os.path.realpath(os.path.join(model.work_dir, filename))
        package_dir = os.path.dirname(os.path.realpath(openc3.__file__))
        if path.startswith(package_dir + os.sep):
            # Import COSMOS microservices by module name so they are loaded only once
            relative = os.path.relpath(path, os.path.dirname(package_dir))
            module = importlib.import_module(relative[: -len(".py")].replace(os.sep, "."))
        else:
            spec = importlib.util.spec_from_file_location(filename_to_class_name(filename), path)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
        return getattr(module, filename_to_class_name(filename))

    def run(self):
        models = self.child_models()
        # System is one per process and the first microservice to set it up
        # decides which targets it has, so set it up for every child first
        target_names = sorted({name for model in models for name in (model.target_names or [])})
        System.setup_targets(target_names, self.temp_dir, scope=self.scope, descriptions=False)
        self.ensure_pool_sizes(models)

        for model in models:
            klass = self.load_class(model)
            microservice = klass(model.name)
            thread = threading.Thread(target=klass.class_run_body, args=[microservice], daemon=True)
            thread.start()
            ThreadManager.instance().register(thread, shutdown_object=microservice)
        # Each child sets the process-wide Logger name so it would be the last
        # child's. Use this microservice's name, which is what Ruby keeps (its
        # Logger keeps the first name), since that code isn't specific to a child.
        # Each child's own logger still has its name.
        Logger.microservice_name = self.name

        if not models:
            # Nothing to run until the operator restarts this with children
            while not self.cancel_thread:
                self.sleeper.sleep(1)
        else:
            ThreadManager.instance().monitor()
            ThreadManager.instance().shutdown()

    # Redis connections every child may use at once: one held while it reads
    # its topics and one for other calls
    CONNECTIONS_PER_CHILD = 2
    DEFAULT_POOL_SIZE = 100

    @classmethod
    def ensure_pool_sizes(cls, models):
        """The children share this process's Redis connection pools, which are
        sized for one microservice. Each child holds a connection while it reads
        its topics, so with too many children some would wait to read."""
        pool_size = cls.DEFAULT_POOL_SIZE + (len(models) * cls.CONNECTIONS_PER_CHILD)
        db_shards = {0} | {int(model.db_shard or 0) for model in models}
        for db_shard in sorted(db_shards):
            Store.instance(db_shard=db_shard).ensure_pool_size(pool_size)
            EphemeralStore.instance(db_shard=db_shard).ensure_pool_size(pool_size)

    def shutdown(self, state="STOPPED"):
        self.sleeper.cancel()
        super().shutdown(state)


if os.path.basename(__file__) == os.path.basename(sys.argv[0]):
    MultiMicroservice.class_run()
    ThreadManager.instance().shutdown()
    ThreadManager.instance().join()
