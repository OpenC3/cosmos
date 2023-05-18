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

import time
import functools
import requests
import logging

from cosmosc2.environment import MAX_RETRY_COUNT
from cosmosc2.exceptions import CosmosError, CosmosRetryError
from cosmosc2.__version__ import __title__

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
            raise CosmosRetryError(err) from exc
        except requests.HTTPError as exc:
            err = f"Error response {exc.response.status_code} while requesting {exc.request.url!r}."
            if 400 >= exc.response.status_code < 500:
                raise CosmosError(err) from exc
            elif 500 >= exc.response.status_code < 600:
                raise CosmosRetryError(err) from exc
        except requests.RequestException as exc:
            err = f"An error occurred while requesting {exc.request.url!r}."
            raise CosmosError(err) from exc

    return _request


def retry_wrapper(func):
    @functools.wraps(func)
    def _request(*args, **kwargs):
        exception = None
        for i in range(0, MAX_RETRY_COUNT):
            try_ = f"request {i} out of {MAX_RETRY_COUNT}"
            try:
                logger.debug("%s", try_)
                value = func(*args, **kwargs)
                return value
            except CosmosRetryError as exc:
                logger.error("%s failed with a retryable error, %s", try_, exc)
                exception = exc
                time.sleep(i ** 4)
            except CosmosError as exc:
                logger.error("%s request failed with an error, %s", try_, exc)
                exception = exc
                break
        raise CosmosError("failed all attempts to pull data") from exception

    return _request
