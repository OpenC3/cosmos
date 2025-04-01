# Copyright 2025 OpenC3, Inc.
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
# if purchased from OpenC3, Inc.

import os
import atexit
import tempfile
import threading
import traceback
import json
from openc3.system.system import System
from openc3.utilities.bucket import Bucket
from openc3.utilities.logger import Logger
from openc3.utilities.metric import Metric
from openc3.utilities.secrets import Secrets
from openc3.utilities.sleeper import Sleeper
from openc3.utilities.store import EphemeralStore
from openc3.utilities.thread_manager import ThreadManager
from openc3.topics.topic import Topic
from openc3.environment import OPENC3_CONFIG_BUCKET
from openc3.models.microservice_model import MicroserviceModel
from openc3.models.microservice_status_model import MicroserviceStatusModel

# TODO:
# OpenC3.require_file 'openc3/utilities/open_telemetry'

openc3_scope = "DEFAULT"


class Microservice:
    @classmethod
    def class_run_body(cls, microservice):
        try:
            MicroserviceStatusModel.set(microservice.as_json(), scope=microservice.scope)
            microservice.state = "RUNNING"
            microservice.run()
            microservice.state = "FINISHED"
        except Exception as err:
            # TODO: Handle SystemExit and SignalException
            # if SystemExit === err or SignalException === err:
            #   microservice.state = 'KILLED'
            # else:
            if microservice:
                microservice.error = err
                microservice.state = "DIED_ERROR"
            Logger.fatal(f"Microservice {microservice.name} dying from exception\n{traceback.format_exc()}")
            microservice.shutdown() # Dying in crash so should try to shutdown
        finally:
            if microservice:
                MicroserviceStatusModel.set(microservice.as_json(), scope=microservice.scope)

    @classmethod
    def class_run(cls, name=None):
        microservice = None
        if name is None:
            name = os.environ.get("OPENC3_MICROSERVICE_NAME")
        microservice = cls(name)
        thread = threading.Thread(target=cls.class_run_body, args=[microservice], daemon=True)
        thread.start()
        ThreadManager.instance().register(thread, shutdown_object=microservice)
        ThreadManager.instance().monitor()
        ThreadManager.instance().shutdown()

    def as_json(self):
        json = {
            "name": self.name,
            "state": self.state,
            "count": self.count,
            "plugin": self.plugin,
        }
        if self.error is not None:
            json["error"] = repr(self.error)
        if self.custom is not None:
            json["custom"] = self.custom.as_json()
        return json

    def __init__(self, name, is_plugin=False):
        self.shutdown_complete = False
        if name is None:
            raise RuntimeError("Microservice must be named")

        self.name = name
        split_name = name.split("__")
        if len(split_name) != 3:
            raise RuntimeError(f"Name {name} doesn't match convention of SCOPE__TYPE__NAME")

        self.scope = split_name[0]
        global openc3_scope
        openc3_scope = self.scope
        self.cancel_thread = False
        self.metric = Metric(microservice=self.name, scope=self.scope)
        Logger.scope = self.scope
        Logger.microservice_name = self.name
        self.logger = Logger()
        self.logger.scope = self.scope
        self.logger.microservice_name = self.name
        self.secrets = Secrets.getClient()

        # OpenC3.setup_open_telemetry(self.name, False)

        # Create temp folder for this microservice
        self.temp_dir = tempfile.TemporaryDirectory()

        # Get microservice configuration from Redis
        self.config = MicroserviceModel.get(self.name, scope=self.scope)
        if self.config:
            self.topics = self.config["topics"]
            self.plugin = self.config["plugin"]
            if self.config["secrets"]:
                self.secrets.setup(self.config["secrets"])
        else:
            self.config = {}
            self.plugin = None
        self.logger.info(f"Microservice initialized with config:\n{self.config}")
        if not hasattr(self, "topics") or self.topics is None:
            self.topics = []
        self.microservice_topic = f"MICROSERVICE__{self.name}"

        # Get configuration for any targets
        self.target_names = self.config.get("target_names")
        if self.target_names is None:
            self.target_names = []
        if not is_plugin:
            System.setup_targets(self.target_names, self.temp_dir.name, scope=self.scope)

        # Use atexit to shutdown cleanly no matter how we die
        atexit.register(self.shutdown)

        self.count = 0
        self.error = None
        self.custom = None
        self.state = "INITIALIZED"
        self.work_dir = self.config.get("work_dir")

        if is_plugin:
            self.config["cmd"]

            # Get Microservice files from bucket storage
            temp_dir = tempfile.TemporaryDirectory()
            bucket = OPENC3_CONFIG_BUCKET
            client = Bucket.getClient()

            prefix = f"{self.scope}/microservices/{self.name}/"
            file_count = 0
            for object in client.list_objects(bucket=bucket, prefix=prefix):
                response_target = os.path.join(temp_dir, object.key.split(prefix)[-1])
                os.makedirs(os.path.dirname(response_target), exist_ok=True)
                client.get_object(bucket=bucket, key=object.key, path=response_target)
                file_count += 1

            # Adjust @work_dir to microservice files downloaded if files and a relative path
            if file_count > 0 and self.work_dir[0] != "/":
                self.work_dir = os.path.join(temp_dir, self.work_dir)

            # TODO: Check Syntax on any python files
            # ruby_filename = None
            #  for part in cmd_array:
            #   if /\.rb$/.match?(part):
            #     ruby_filename = part
            #     break
            # if ruby_filename:
            #   OpenC3.set_working_dir(self.work_dir) do
            #     if os.path.exist(ruby_filename):
            #       # Run ruby syntax so we can log those
            #       syntax_check, _ = Open3.capture2e("ruby -c {ruby_filename}")
            #       if /Syntax OK/.match?(syntax_check):
            #         self.logger.info("Ruby microservice {self.name} file {ruby_filename} passed syntax check\n", scope: self.scope)
            #       else:
            #         self.logger.error("Ruby microservice {self.name} file {ruby_filename} failed syntax check\n{syntax_check}", scope: self.scope)
            #     else:
            #       self.logger.error("Ruby microservice {self.name} file {ruby_filename} does not exist", scope: self.scope)
        else:
            self.microservice_status_sleeper = Sleeper()
            self.microservice_status_period_seconds = 5
            self.microservice_status_thread = threading.Thread(target=self._status_thread, daemon=True)
            self.microservice_status_thread.start()
            ThreadManager.instance().register(self.microservice_status_thread)

    # Must be implemented by a subclass
    def run(self):
        self.shutdown()

    def shutdown(self):
        if self.shutdown_complete:
            return  # Nothing more to do
        self.logger.info(f"Shutting down microservice: {self.name}")
        self.cancel_thread = True
        if self.microservice_status_sleeper:
            self.microservice_status_sleeper.cancel()
        MicroserviceStatusModel.set(self.as_json(), scope=self.scope)
        if self.temp_dir is not None:
            self.temp_dir.cleanup()
        self.metric.shutdown()
        self.logger.debug(f"Shutting down microservice complete: {self.name}")
        self.shutdown_complete = True

    def setup_microservice_topic(self):
        self.topics.append(self.microservice_topic)
        thread_id = threading.get_native_id()
        ephemeral_store_instance = EphemeralStore.instance()
        if thread_id not in ephemeral_store_instance.topic_offsets:
            ephemeral_store_instance.topic_offsets[thread_id] = {}
        ephemeral_store_instance.topic_offsets[thread_id][self.microservice_topic] = "0-0"

    # Returns if the command was handled
    def microservice_cmd(self, topic, msg_id, msg_hash, _):
        command = msg_hash.get("command")
        if command == "ADD_TOPICS" and msg_hash.get("topics"):
            topics = json.loads(msg_hash["topics"])
            if topics and isinstance(topics, list):
                for new_topic in topics:
                    if new_topic not in self.topics:
                        self.topics.append(new_topic)
            else:
                raise RuntimeError(f"Invalid topics given to microservice_cmd: {topics}")
            Topic.trim_topic(topic, msg_id)
            return True
        Topic.trim_topic(topic, msg_id)
        return False

    def _status_thread(self):
        while not self.cancel_thread:
            try:
                MicroserviceStatusModel.set(self.as_json(), scope=self.scope)
                if self.microservice_status_sleeper.sleep(self.microservice_status_period_seconds):
                    break
            except RuntimeError as error:
                self.logger.error(f"{self.name} status thread died: {repr(error)}")
                raise error
