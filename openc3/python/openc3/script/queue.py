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

import json
from openc3.script import API_SERVER
from openc3.environment import OPENC3_SCOPE


def _make_request(action, verb, uri, scope, data=None):
    """Helper function that makes the request and parses the response"""
    kwargs = {'scope': scope}
    if data is not None:
        kwargs['data'] = data
        kwargs['json'] = True

    response = API_SERVER.request(verb, uri, **kwargs)

    if response is None:
        raise RuntimeError(f"Failed to {action} queue. No response from server.")
    elif response.status_code not in [200, 201]:
        try:
            result = json.loads(response.text)
            message = result.get('message', 'Unknown error')
        except (json.JSONDecodeError, AttributeError):
            message = 'Unknown error'
        raise RuntimeError(f"Failed to {action} queue due to {message}")

    return json.loads(response.text)


def queue_all(scope: str = OPENC3_SCOPE):
    """Get all queues"""
    return _make_request('index', 'get', '/openc3-api/queues', scope)


def queue_get(name, scope: str = OPENC3_SCOPE):
    """Get a specific queue"""
    return _make_request('get', 'get', f'/openc3-api/queues/{name}', scope)


def queue_list(name, scope: str = OPENC3_SCOPE):
    """List contents of a queue"""
    return _make_request('list', 'get', f'/openc3-api/queues/{name}/list', scope)


def queue_create(name, scope: str = OPENC3_SCOPE):
    """Create a new queue"""
    return _make_request('create', 'post', f'/openc3-api/queues/{name}', scope)


def queue_hold(name, scope: str = OPENC3_SCOPE):
    """Hold a queue (pause processing)"""
    return _make_request('hold', 'post', f'/openc3-api/queues/{name}/hold', scope)


def queue_release(name, scope: str = OPENC3_SCOPE):
    """Release a held queue (resume processing)"""
    return _make_request('release', 'post', f'/openc3-api/queues/{name}/release', scope)


def queue_disable(name, scope: str = OPENC3_SCOPE):
    """Disable a queue"""
    return _make_request('disable', 'post', f'/openc3-api/queues/{name}/disable', scope)


def queue_exec(name, index=None, scope: str = OPENC3_SCOPE):
    """Pop a value from the queue at the specified index or first value if no index"""
    uri = f'/openc3-api/queues/{name}/exec_command'
    return _make_request('pop', 'delete', uri, scope, data={'index': index} if index is not None else None)


def queue_delete(name, scope: str = OPENC3_SCOPE):
    """Delete a queue"""
    return _make_request('delete', 'delete', f'/openc3-api/queues/{name}', scope)


# Alias for queue_delete to match Ruby implementation
queue_destroy = queue_delete
