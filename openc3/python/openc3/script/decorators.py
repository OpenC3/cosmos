# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# Modified by OpenC3, Inc.
# All changes Copyright 2023, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import functools

import requests


def request_wrapper(func):
    @functools.wraps(func)
    def _request(*args, **kwargs):
        try:
            value = func(*args, **kwargs)
            return value
        except ValueError as exc:
            err = f"ValueError {exc} while requesting token."
            raise RuntimeError(err) from exc
        except requests.Timeout as exc:
            err = f"Timeout error while requesting {exc.request.url!r}"
            raise RuntimeError(err) from exc
        except requests.HTTPError as exc:
            err = f"Error response {exc.response.status_code} while requesting {exc.request.url!r}."
            if exc.response.status_code <= 400:
                raise RuntimeError(err) from exc
        except requests.RequestException as exc:
            err = f"An error occurred while requesting {exc.request.url!r}."
            raise RuntimeError(err) from exc

    return _request
