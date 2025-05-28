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

import json
from datetime import datetime, timezone
from openc3.models.model import Model
from openc3.utilities.store import openc3_redis_cluster

class ScriptStatusModel(Model):
    # Note: ScriptRunner only has permissions for keys that start with running-script
    RUNNING_PRIMARY_KEY = 'running-script'
    COMPLETED_PRIMARY_KEY = 'running-script-completed'

    @property
    def id(self):
        return self.name

    # NOTE: The following three class methods are used by the ModelController
    # and are reimplemented to enable various Model class methods to work
    @classmethod
    def get(cls, name, scope, type = "auto"):
        if type == "auto" or type == "running":
            # Check for running first
            running = super().get(f"{cls.RUNNING_PRIMARY_KEY}__{scope}", name = name)
            if running:
                return running
        return super().get(f"{cls.COMPLETED_PRIMARY_KEY}__{scope}", name = name)

    @classmethod
    def names(cls, scope, type = "running"):
        if type == "running":
            return super().names(f"{cls.RUNNING_PRIMARY_KEY}__{scope}")
        else:
            return super().names(f"{cls.COMPLETED_PRIMARY_KEY}__{scope}")

    @classmethod
    def all(cls, scope, offset = 0, limit = 10, type = "running"):
        if type == "running":
            keys = cls.store().zrevrange(f"{cls.RUNNING_PRIMARY_KEY}__{scope}__LIST", int(offset), int(offset) + int(limit) - 1)
            if len(keys) == 0:
                return []
            with cls.store().instance().redis_pool.get() as redis:
                result = []
                if openc3_redis_cluster:
                    # No pipelining for cluster mode
                    # because it requires using the same shard for all keys
                    for key in keys:
                        result.append(redis.hget(f"{cls.RUNNING_PRIMARY_KEY}__{scope}", key))
                else:
                    pipeline = redis.pipeline(transaction=False)
                    for key in keys:
                        pipeline.hget(f"{cls.RUNNING_PRIMARY_KEY}__{scope}", key)
                    result = pipeline.execute()
                for i in range(len(result)):
                    if result[i] is not None:
                        result[i] = json.loads(result[i])
                return result
        else:
            keys = cls.store().zrevrange(f"{cls.COMPLETED_PRIMARY_KEY}__{scope}__LIST", int(offset), int(offset) + int(limit) - 1)
            if len(keys) == 0:
                return []
            with cls.store().instance().redis_pool.get() as redis:
                result = []
                if openc3_redis_cluster:
                    # No pipelining for cluster mode
                    # because it requires using the same shard for all keys
                    for key in keys:
                        result.append(redis.hget(f"{cls.COMPLETED_PRIMARY_KEY}__{scope}", key))
                else:
                    pipeline = redis.pipeline(transaction=False)
                    for key in keys:
                        pipeline.hget(f"{cls.COMPLETED_PRIMARY_KEY}__{scope}", key)
                    result = pipeline.execute()
                for i in range(len(result)):
                    if result[i] is not None:
                        result[i] = json.loads(result[i])
                return result

    @classmethod
    def count(cls, scope, type = "running"):
        if type == "running":
            return cls.store().zcount(f"{cls.RUNNING_PRIMARY_KEY}__#{scope}__LIST", 0, "+inf")
        else:
            return cls.store().zcount(f"{cls.COMPLETED_PRIMARY_KEY}__#{scope}__LIST", 0, "+inf")

    def __init__(
        self,
        name, # id
        state, # spawning, init, running, paused, waiting, error, breakpoint, crashed, stopped, completed, completed_errors, killed
        shard = 0, # Future enhancement of script runner shards
        filename = "", # The initial filename
        current_filename = None, # The current filename
        line_no = 0, # The current line number
        start_line_no = 1, # The line number to start the script at
        end_line_no = None, # The line number to end the script at
        username = None, # The username of the person who started the script
        user_full_name = None, # The full name of the person who started the script
        start_time = None, # The time the script started ISO format
        end_time = None, # The time the script ended ISO format
        disconnect = False,
        environment = None,
        suite_runner = None,
        errors = None,
        pid = None,
        log = None,
        report = None,
        updated_at = None,
        scope = None
    ):
        self.__state = state
        if self.is_complete():
            super().__init__(f"{self.COMPLETED_PRIMARY_KEY}__{scope}", name = name, updated_at = updated_at, plugin = None, scope = scope)
        else:
            super().__init__(f"{self.RUNNING_PRIMARY_KEY}__{scope}", name = name, updated_at = updated_at, plugin = None, scope = scope)
        self.shard = int(shard)
        self.filename = filename
        self.current_filename = current_filename
        self.line_no = line_no
        self.start_line_no = start_line_no
        self.end_line_no = end_line_no
        self.username = username
        self.user_full_name = user_full_name
        self.start_time = start_time
        self.end_time = end_time
        self.disconnect = disconnect
        self.environment = environment
        self.suite_runner = suite_runner
        self.errors = errors
        self.pid = pid
        self.log = log
        self.report = report

    def is_complete(self):
        return (self.__state == 'completed' or self.__state == 'completed_errors' or self.__state == 'stopped' or self.__state == 'crashed' or self.__state == 'killed')

    @property
    def state(self):
        return self.__state

    @state.setter
    def state(self, new_state):
        # If the state is already a flavor of complete, leave it alone (first wins)
        if not self.is_complete():
            self.__state = new_state
            # If setting to complete, check for errors
            # and set the state to completed_errors if they exist
            if self.__state == 'completed' and self.errors:
                self.__state = 'completed_errors'

    # Update the Redis hash at primary_key and set the field "name"
    # to the JSON generated via calling as_json
    def create(self, update = False, force = False, queued = False, isoformat = True):
        self.updated_at = datetime.now(timezone.utc).isoformat()

        if queued:
            write_store = self.store_queued()
        else:
            write_store = self.store()
        write_store.hset(self.primary_key, self.name, json.dumps(self.as_json()))

        # Also add to ordered set on create
        if not update:
            mapping = {}
            mapping[self.name] = int(self.name)
            write_store.zadd(self.primary_key + "__LIST", mapping)

    def update(self, force = False, queued = False):
        # Magically handle the change from running to completed
        if self.is_complete() and self.primary_key == f"{self.RUNNING_PRIMARY_KEY}__{self.scope}":
            # Destroy the running key
            self.destroy(queued = queued)
            self.destroyed = False

            # Move to completed
            self.primary_key = f"{self.COMPLETED_PRIMARY_KEY}__{self.scope}"
            self.create(update = False, force = force, queued = queued, isoformat = True)
        else:
            self.create(update = True, force = force, queued = queued, isoformat = True)

    # Delete the model from the Store
    def destroy(self, queued = False):
        self.destroyed = True
        self.undeploy()
        if queued:
            write_store = self.store_queued()
        else:
            write_store = self.store()
        write_store.hdel(self.primary_key, self.name)
        # Also remove from ordered set
        write_store.zremrangebyscore(self.primary_key + "__LIST", int(self.name), int(self.name))

    def as_json(self):
        return {
            'name': self.name,
            'state': self.__state,
            'shard': self.shard,
            'filename': self.filename,
            'current_filename': self.current_filename,
            'line_no': self.line_no,
            'start_line_no': self.start_line_no,
            'end_line_no': self.end_line_no,
            'username': self.username,
            'user_full_name': self.user_full_name,
            'start_time': self.start_time,
            'end_time': self.end_time,
            'disconnect': self.disconnect,
            'environment': self.environment,
            'suite_runner': self.suite_runner,
            'errors': self.errors,
            'pid': self.pid,
            'log': self.log,
            'report': self.report,
            'updated_at': self.updated_at,
            'scope': self.scope
        }
