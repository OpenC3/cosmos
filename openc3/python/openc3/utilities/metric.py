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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import time
import threading
from openc3.models.metric_model import MetricModel
from openc3.utilities.sleeper import Sleeper
from openc3.top_level import kill_thread


class Metric:
    # The update interval. How often in seconds metrics are updated by this process
    UPDATE_INTERVAL = 5

    # Mutex protecting class variables
    mutex = threading.Lock()

    # Array of instances used to keep track of metrics
    instances = []

    # Thread used to post metrics across all classes
    update_thread = None

    # Sleeper used to delay update thread
    update_sleeper = None

    # Objects with a generate method to be called on each metric cycle (to generate metrics)
    update_generators = []

    def __init__(self, microservice, scope):
        self.scope = scope
        self.microservice = microservice
        self.data = {}
        self.mutex = threading.Lock()

        # Always make sure there is a update thread
        with Metric.mutex:
            Metric.instances.append(self)
            if Metric.update_thread is None:
                Metric.update_thread = threading.Thread(
                    target=self.update_thread_body,
                    daemon=True,
                )
                Metric.update_thread.start()

    def set(self, name, value, type=None, unit=None, help=None, labels=None, time_ms=None):
        with self.mutex:
            if self.data.get(name) is None:
                self.data[name] = {}
            self.data[name]["value"] = value
            if type:
                self.data[name]["type"] = type
            if unit:
                self.data[name]["unit"] = unit
            if help:
                self.data[name]["help"] = help
            if labels:
                self.data[name]["labels"] = labels
            if time_ms:
                self.data[name]["time_ms"] = time_ms

    def set_multiple(self, data):
        with self.mutex:
            self.data = self.data | data

    def update_thread_body(self):
        Metric.update_sleeper = Sleeper()
        while True:
            start_time = time.time()

            with Metric.mutex:
                for generator in Metric.update_generators:
                    generator.generate(Metric.instances[0])

                for instance in Metric.instances:
                    with instance.mutex:
                        json = {}
                        json["name"] = instance.microservice
                        values = instance.data
                        json["values"] = values
                        if len(values) > 0:
                            MetricModel.set(json, scope=instance.scope)

            # Only check whether to update at a set interval
            run_time = time.time() - start_time
            sleep_time = Metric.UPDATE_INTERVAL - run_time
            if sleep_time < 0:
                sleep_time = 0
            if Metric.update_sleeper.sleep(sleep_time):
                break

    def shutdown(self):
        with Metric.mutex:
            try:
                Metric.instances.remove(self)
            except ValueError:
                pass
            if len(Metric.instances) <= 0:
                if Metric.update_sleeper:
                    Metric.update_sleeper.cancel()
                if Metric.update_thread:
                    kill_thread(self, Metric.update_thread)
                Metric.update_thread = None

    def graceful_kill(self):
        pass

    @classmethod
    def add_update_generator(cls, object):
        Metric.update_generators.append(object)
