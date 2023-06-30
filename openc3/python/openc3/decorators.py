#!/usr/bin/env python3
# vim: tabstop=8 expandtab shiftwidth=4 softtabstop=4
# -*- coding: latin-1 -*-
"""
decorators.py
"""

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Lesser General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt

# Modified by OpenC3, Inc.
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import functools
import requests
import logging

from openc3.exceptions import CosmosError
from openc3.__version__ import __title__

logger = logging.getLogger(__title__)

def request_wrapper(func):
    @functools.wraps(func)
    def _request(*args, **kwargs):
        try:
            value = func(*args, **kwargs)
            return value
        except ValueError as exc:
            err = f"ValueError {exc} while requesting token."
            raise CosmosError(err) from exc
        except requests.Timeout as exc:
            err = f"Timeout error while requesting {exc.request.url!r}"
            raise CosmosError(err) from exc
        except requests.HTTPError as exc:
            err = f"Error response {exc.response.status_code} while requesting {exc.request.url!r}."
            if 400 >= exc.response.status_code:
                raise CosmosError(err) from exc
        except requests.RequestException as exc:
            err = f"An error occurred while requesting {exc.request.url!r}."
            raise CosmosError(err) from exc

    return _request