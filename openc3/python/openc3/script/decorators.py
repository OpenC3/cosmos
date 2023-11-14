# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Lesser General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt

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
            if 400 >= exc.response.status_code:
                raise RuntimeError(err) from exc
        except requests.RequestException as exc:
            err = f"An error occurred while requesting {exc.request.url!r}."
            raise RuntimeError(err) from exc

    return _request
