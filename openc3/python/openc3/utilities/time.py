# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.


from datetime import datetime, timezone


NSEC_PER_SECOND = 1_000_000_000


def from_nsec_from_epoch(nsec_from_epoch):
    if nsec_from_epoch is None:
        nsec_from_epoch = datetime().now(timezone.utc)
    return datetime.fromtimestamp(nsec_from_epoch / NSEC_PER_SECOND, timezone.utc)


def to_nsec_from_epoch(time):
    if time is None:
        return 0
    return int(time.timestamp()) * NSEC_PER_SECOND + time.microsecond * 1000


# @return [String] Date formatted as YYYYMMDDHHmmSSNNNNNNNNN
def to_timestamp(time):
    return time.strftime("%Y%m%d%H%M%S%f000")


def formatted(time):
    return time.strftime("%Y/%m/%d %H:%M:%S.%f")[:-3]
