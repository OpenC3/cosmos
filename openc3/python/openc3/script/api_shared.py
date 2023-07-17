#!/usr/bin/env python3

# Copyright 2022 Ball Aerospace & Technologies Corp.
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

# Modified by OpenC3, Inc.
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import time

from openc3.__version__ import __title__
from openc3.script import DISCONNECT
from .extract import *
from .telemetry import *
from .exceptions import CheckError
from openc3.utilities.logger import Logger
from openc3.environment import *

DEFAULT_TLM_POLLING_RATE = 0.25


def check(*args, type="CONVERTED", scope="DEFAULT"):
    print(f"type:{type} scope:{scope}")
    """Check the converted value of a telmetry item against a condition
    Always print the value of the telemetry item to STDOUT
    If the condition check fails, raise an error
    Supports two signatures:
    check(target_name, packet_name, item_name, comparison_to_eval)
    or
    check('target_name packet_name item_name > 1')
    """
    match type:
        case "CONVERTED":
            return _check(telemetry.tlm, *args)
        case "RAW":
            return _check(telemetry.tlm_raw, *args)
        case "FORMATTED":
            return _check(telemetry.tlm_formatted, *args)
        case "WITH_UNITS":
            return _check(telemetry.tlm_with_units, *args)


def check_formatted(*args):
    """Check the formatted value of a telmetry item against a condition
    Always print the value of the telemetry item to STDOUT
    If the condition check fails, raise an error
    Supports two signatures:
    check(target_name, packet_name, item_name, comparison_to_eval)
    or
    check('target_name packet_name item_name > 1')
    """
    return _check(telemetry.tlm_formatted, *args)


def check_with_units(*args):
    """Check the formatted with units value of a telmetry item against a condition
    Always print the value of the telemetry item to STDOUT
    If the condition check fails, raise an error
    Supports two signatures:
    check(target_name, packet_name, item_name, comparison_to_eval)
    or
    check('target_name packet_name item_name > 1')
    """
    return _check(telemetry.tlm_with_units, *args)


def check_raw(*args):
    """Check the raw value of a telmetry item against a condition
    Always print the value of the telemetry item to STDOUT
    If the condition check fails, raise an error
    Supports two signatures:
    check(target_name, packet_name, item_name, comparison_to_eval)
    or
    check('target_name packet_name item_name > 1')
    """
    return _check(telemetry.tlm_raw, *args)


def _check_tolerance(method, *args):
    (
        target_name,
        packet_name,
        item_name,
        expected_value,
        tolerance,
    ) = _check_tolerance_process_args(args, "check_tolerance")
    value = method(target_name, packet_name, item_name)
    if isinstance(value, list):
        expected_value, tolerance = array_tolerance_process_args(
            len(value), expected_value, tolerance, "check_tolerance"
        )

        message = ""
        all_checks_ok = True
        for i in range(len(value)):
            range_bottom = expected_value[i] - tolerance[i]
            range_top = expected_value[i] + tolerance[i]
            check_str = "CHECK: {:s}[{:d}]".format(
                _upcase(target_name, packet_name, item_name), i
            )
            range_str = "range {:g} to {:g} with value == {:g}".format(
                range_bottom, range_top, value[i]
            )
            if value[i] >= range_bottom and value[i] <= range_top:
                message += "{:s} was within #{:s}\n".format(check_str, range_str)
            else:
                message += "{:s} failed to be within {:s}\n".format(
                    check_str, range_str
                )
                all_checks_ok = False

        if all_checks_ok:
            Logger.info(message)
        else:
            raise CheckError(message)
    else:
        range_bottom = expected_value - tolerance
        range_top = expected_value + tolerance
        check_str = "CHECK: {:s}".format(_upcase(target_name, packet_name, item_name))
        range_str = "range {:g} to {:g} with value == {:g}".format(
            range_bottom, range_top, value
        )
        if value >= range_bottom and value <= range_top:
            Logger.info("{:s} was within {:s}".format(check_str, range_str))
        else:
            message = "{:s} failed to be within {:s}".format(check_str, range_str)
            raise CheckError(message)


def check_tolerance(*args):
    """Check the converted value of a telmetry item against an expected value with a tolerance
    Always print the value of the telemetry item to STDOUT
    If the condition check fails, raise an error
    Supports two signatures:
    check_tolerance(target_name, packet_name, item_name, expected_value, tolerance)
    or
    check_tolerance('target_name packet_name item_name', expected_value, tolerance)
    """
    return _check_tolerance(telemetry.tlm, *args)


def check_tolerance_raw(*args):
    """Check the raw value of a telmetry item against an expected value with a tolerance
    Always print the value of the telemetry item to STDOUT
    If the condition check fails, raise an error
    Supports two signatures:
    check_tolerance_raw(target_name, packet_name, item_name, expected_value, tolerance)
    or
    check_tolerance_raw('target_name packet_name item_name', expected_value, tolerance)
    """
    return _check_tolerance(telemetry.tlm_raw, *args)


def check_expression(exp_to_eval, locals=None):
    """Check to see if an expression is true without waiting.  If the expression
    is not true, the script will pause."""
    success = cosmos_script_wait_implementation_expression(
        exp_to_eval, 0, DEFAULT_TLM_POLLING_RATE, locals
    )
    if success:
        Logger.info("CHECK: {:s} is TRUE".format(exp_to_eval))
    else:
        message = "CHECK: {:s} is FALSE".format(exp_to_eval)
        raise CheckError(message)


def wait(*args):
    """Wait on an expression to be true.  On a timeout, the script will continue.
    Supports multiple signatures:
    wait(time)
    wait('target_name packet_name item_name > 1', timeout, polling_rate)
    wait('target_name', 'packet_name', 'item_name', comparison_to_eval, timeout, polling_rate)
    """
    wait_process_args(args, "wait", "CONVERTED")


def wait_raw(*args):
    """Wait on an expression to be true.  On a timeout, the script will continue.
    Supports multiple signatures:
    wait(time)
    wait_raw('target_name packet_name item_name > 1', timeout, polling_rate)
    wait_raw('target_name', 'packet_name', 'item_name', comparison_to_eval, timeout, polling_rate)
    """
    wait_process_args(args, "wait_raw", "RAW")


def _wait_tolerance(raw, *args):
    if raw:
        type = "RAW"
    else:
        type = "CONVERTED"
    type_string = "wait_tolerance"
    if raw:
        type_string += "_raw"
    (
        target_name,
        packet_name,
        item_name,
        expected_value,
        tolerance,
        timeout,
        polling_rate,
    ) = wait_tolerance_process_args(args, type_string)
    start_time = time.time()
    value = telemetry.tlm_variable(target_name, packet_name, item_name, type)
    if isinstance(value, list):
        expected_value, tolerance = array_tolerance_process_args(
            len(value), expected_value, tolerance, type_string
        )
        success, value = cosmos_script_wait_implementation_array_tolerance(
            len(value),
            target_name,
            packet_name,
            item_name,
            type,
            expected_value,
            tolerance,
            timeout,
            polling_rate,
        )
        time_float = time.time() - start_time

        message = ""
        for i in range(0, len(value)):
            range_bottom = expected_value[i] - tolerance[i]
            range_top = expected_value[i] + tolerance[i]
            check_str = "WAIT: {:s}[{:d}]".format(
                _upcase(target_name, packet_name, item_name), i
            )
            range_str = "range {:g} to {:g} with value == {:g} after waiting {:g} seconds".format(
                range_bottom, range_top, value[i], time_float
            )
            if value[i] >= range_bottom and value[i] <= range_top:
                message += "{:s} was within #{:s}\n".format(check_str, range_str)
            else:
                message += "{:s} failed to be within {:s}\n".format(
                    check_str, range_str
                )

        if success:
            Logger.info(message)
        else:
            Logger.warn(message)
    else:
        success, value = cosmos_script_wait_implementation_tolerance(
            target_name,
            packet_name,
            item_name,
            type,
            expected_value,
            tolerance,
            timeout,
            polling_rate,
        )
        time_float = time.time() - start_time
        range_bottom = expected_value - tolerance
        range_top = expected_value + tolerance
        wait_str = "WAIT: {:s}".format(_upcase(target_name, packet_name, item_name))
        range_str = (
            "range {:g} to {:g} with value == {:g} after waiting {:g} seconds".format(
                range_bottom, range_top, value, time_float
            )
        )
        if success:
            Logger.info("{:s} was within {:s}".format(wait_str, range_str))
        else:
            Logger.warning("{:s} failed to be within {:s}".format(wait_str, range_str))
    return time_float


def wait_tolerance(*args):
    """Wait on an expression to be true.  On a timeout, the script will continue.
    Supports multiple signatures:
    wait_tolerance('target_name packet_name item_name', expected_value, tolerance, timeout, polling_rate)
    wait_tolerance('target_name', 'packet_name', 'item_name', expected_value, tolerance, timeout, polling_rate)
    """
    return _wait_tolerance(False, *args)


def wait_tolerance_raw(*args):
    """Wait on an expression to be true.  On a timeout, the script will continue.
    Supports multiple signatures:
    wait_tolerance_raw('target_name packet_name item_name', expected_value, tolerance, timeout, polling_rate)
    wait_tolerance_raw('target_name', 'packet_name', 'item_name', expected_value, tolerance, timeout, polling_rate)
    """
    return _wait_tolerance(True, *args)


def wait_expression(
    exp_to_eval, timeout, polling_rate=DEFAULT_TLM_POLLING_RATE, locals=None
):
    """Wait on a custom expression to be true"""
    start_time = time.time()
    success = cosmos_script_wait_implementation_expression(
        exp_to_eval, timeout, polling_rate, locals
    )
    time_float = time.time() - start_time
    if success:
        Logger.info(
            "WAIT: {:s} is TRUE after waiting {:g} seconds".format(
                exp_to_eval, time_float
            )
        )
    else:
        Logger.warning(
            "WAIT: {:s} is FALSE after waiting {:g} seconds".format(
                exp_to_eval, time_float
            )
        )
    return time_float


def _wait_check(raw, *args):
    if raw:
        type = "RAW"
    else:
        type = "CONVERTED"
    (
        target_name,
        packet_name,
        item_name,
        comparison_to_eval,
        timeout,
        polling_rate,
    ) = wait_check_process_args(args, "wait_check")
    start_time = time.time()
    success, value = openc3_script_wait_implementation(
        target_name,
        packet_name,
        item_name,
        type,
        comparison_to_eval,
        timeout,
        polling_rate,
    )
    time_float = time.time() - start_time
    check_str = "CHECK: {:s} {:s}".format(
        _upcase(target_name, packet_name, item_name), comparison_to_eval
    )
    with_value_str = "with value == {:s} after waiting {:g} seconds".format(
        str(value), time_float
    )
    if success:
        Logger.info("{:s} success {:s}".format(check_str, with_value_str))
    else:
        message = "{:s} failed {:s}".format(check_str, with_value_str)
        raise CheckError(message)
    return time_float


def wait_check(*args):
    """Wait for the converted value of a telmetry item against a condition or for a timeout
    and then check against the condition
    Supports two signatures:
    wait_check(target_name, packet_name, item_name, comparison_to_eval, timeout, polling_rate)
    or
    wait_check('target_name packet_name item_name > 1', timeout, polling_rate)"""
    return _wait_check(False, *args)


def wait_check_raw(*args):
    """Wait for the raw value of a telmetry item against a condition or for a timeout
    and then check against the condition
    Supports two signatures:
    wait_check_raw(target_name, packet_name, item_name, comparison_to_eval, timeout, polling_rate)
    or
    wait_check_raw('target_name packet_name item_name > 1', timeout, polling_rate)"""
    return _wait_check(True, *args)


def _wait_check_tolerance(raw, *args):
    type_string = "wait_check_tolerance"
    if raw:
        type_string += "_raw"
    if raw:
        type = "RAW"
    else:
        type = "CONVERTED"
    (
        target_name,
        packet_name,
        item_name,
        expected_value,
        tolerance,
        timeout,
        polling_rate,
    ) = wait_tolerance_process_args(args, type_string)
    start_time = time.time()
    value = telemetry.tlm_variable(target_name, packet_name, item_name, type)
    if isinstance(value, list):
        expected_value, tolerance = array_tolerance_process_args(
            len(value), expected_value, tolerance, type_string
        )
        success, value = cosmos_script_wait_implementation_array_tolerance(
            len(value),
            target_name,
            packet_name,
            item_name,
            type,
            expected_value,
            tolerance,
            timeout,
            polling_rate,
        )
        time_float = time.time() - start_time

        message = ""
        for i in range(0, len(value)):
            range_bottom = expected_value[i] - tolerance[i]
            range_top = expected_value[i] + tolerance[i]
            check_str = "WAIT: {:s}[{:d}]".format(
                _upcase(target_name, packet_name, item_name), i
            )
            range_str = "range {:g} to {:g} with value == {:g} after waiting {:g} seconds".format(
                range_bottom, range_top, value[i], time_float
            )
            if value[i] >= range_bottom and value[i] <= range_top:
                message += "{:s} was within #{:s}\n".format(check_str, range_str)
            else:
                message += "{:s} failed to be within {:s}\n".format(
                    check_str, range_str
                )

        if success:
            Logger.info(message)
        else:
            raise CheckError(message)
    else:
        success, value = cosmos_script_wait_implementation_tolerance(
            target_name,
            packet_name,
            item_name,
            type,
            expected_value,
            tolerance,
            timeout,
            polling_rate,
        )
        time_float = time.time() - start_time
        range_bottom = expected_value - tolerance
        range_top = expected_value + tolerance
        check_str = "CHECK: {:s}".format(_upcase(target_name, packet_name, item_name))
        range_str = (
            "range {:g} to {:g} with value == {:g} after waiting {:g} seconds".format(
                range_bottom, range_top, value, time_float
            )
        )
        if success:
            Logger.info("{:s} was within {:s}".format(check_str, range_str))
        else:
            message = "{:s} failed to be within {:s}".format(check_str, range_str)
            raise CheckError(message)
    return time_float


def wait_check_tolerance(*args):
    _wait_check_tolerance(False, *args)


def wait_check_tolerance_raw(*args):
    _wait_check_tolerance(True, *args)


def wait_check_expression(
    exp_to_eval, timeout, polling_rate=DEFAULT_TLM_POLLING_RATE, context=None
):
    """Wait on an expression to be true.  On a timeout, the script will pause"""
    start_time = time.time()
    success = cosmos_script_wait_implementation_expression(
        exp_to_eval, timeout, polling_rate, context
    )
    time_float = time.time() - start_time
    if success:
        Logger.info(
            "CHECK: {:s} is TRUE after waiting {:g} seconds".format(
                exp_to_eval, time_float
            )
        )
    else:
        message = "CHECK: {:s} is FALSE after waiting {:g} seconds".format(
            exp_to_eval, time_float
        )
        raise CheckError(message)
    return time_float


def wait_expression_stop_on_timeout(*args):
    return wait_check_expression(*args)


def wait_packet(
    target_name,
    packet_name,
    num_packets,
    timeout,
    polling_rate=DEFAULT_TLM_POLLING_RATE,
):
    return _wait_packet(
        False, target_name, packet_name, num_packets, timeout, polling_rate
    )


def wait_check_packet(
    target_name,
    packet_name,
    num_packets,
    timeout,
    polling_rate=DEFAULT_TLM_POLLING_RATE,
):
    """Wait for a telemetry packet to be received a certain number of times or timeout and raise an error"""
    return _wait_packet(
        True, target_name, packet_name, num_packets, timeout, polling_rate
    )


###########################################################################
# Private implementation details
###########################################################################


def _upcase(target_name, packet_name, item_name):
    """Creates a string with the parameters upcased"""
    return "{:s} {:s} {:s}".format(
        target_name.upper(), packet_name.upper(), item_name.upper()
    )


def _check(method, *args):
    """Implementation of the various check commands. It yields back to the
    caller to allow the return of the value through various telemetry calls.
    This method should not be called directly by application code."""
    target_name, packet_name, item_name, comparison_to_eval = _check_process_args(
        args, "check"
    )
    value = method(target_name, packet_name, item_name)
    if comparison_to_eval:
        return check_eval(
            target_name, packet_name, item_name, comparison_to_eval, value
        )
    else:
        Logger.info(
            "CHECK: %s == %s", _upcase(target_name, packet_name, item_name), str(value)
        )


def _check_process_args(args, function_name):
    match len(args):
        case 1:
            (
                target_name,
                packet_name,
                item_name,
                comparison_to_eval,
            ) = extract.extract_fields_from_check_text(args[0])
        case 4:
            target_name = args[0]
            packet_name = args[1]
            item_name = args[2]
            comparison_to_eval = args[3]
        case _:
            # Invalid number of arguments
            raise RuntimeError(
                f"ERROR: Invalid number of arguments ({len(args)}) passed to {function_name}()"
            )
    return [target_name, packet_name, item_name, comparison_to_eval]


def _check_tolerance_process_args(args, function_name):
    match len(args):
        case 3:
            target_name, packet_name, item_name = extract.extract_fields_from_tlm_text(
                args[0]
            )
            expected_value = args[1]
            tolerance = abs(args[2])
        case 5:
            target_name = args[0]
            packet_name = args[1]
            item_name = args[2]
            expected_value = args[3]
            tolerance = abs(args[4])
        case _:
            # Invalid number of arguments
            raise RuntimeError(
                f"ERROR: Invalid number of arguments ({len(args)}) passed to {function_name}()"
            )
    return [target_name, packet_name, item_name, expected_value, tolerance]


def _wait_packet(
    check,
    target_name,
    packet_name,
    num_packets,
    timeout,
    polling_rate=DEFAULT_TLM_POLLING_RATE,
    quiet=False,
    scope=OPENC3_SCOPE,
):
    """Wait for a telemetry packet to be received a certain number of times or timeout"""
    if check:
        type = "CHECK"
    else:
        type = "WAIT"
    initial_count = telemetry.tlm(
        target_name, packet_name, "RECEIVED_COUNT", scope=scope
    )
    # If the packet has not been received the initial_count could be None
    if not initial_count:
        initial_count = 0
    start_time = time.time()
    success, value = openc3_script_wait_implementation(
        target_name,
        packet_name,
        "RECEIVED_COUNT",
        "CONVERTED",
        f">= {initial_count + num_packets}",
        timeout,
        polling_rate,
    )
    # If the packet has not been received the value could be None
    if not value:
        value = 0
    time = time.time() - start_time
    if success:
        if not quiet:
            Logger.info(
                "{:s}: {:s} {:s} received {:d} times after waiting {:g} seconds".format(
                    type,
                    target_name.upper(),
                    packet_name.upper(),
                    value - initial_count,
                    time,
                )
            )
    else:
        message = "{:s}: {:s} {:s} expected to be received {:d} times but only received {:d} times after waiting {:g} seconds".format(
            type,
            target_name.upper(),
            packet_name.upper(),
            num_packets,
            value - initial_count,
            time,
        )
        if check:
            # TODO: Handle disconnect
            raise CheckError(message)
        elif not quiet:
            Logger.warn(message)
    return time


def _execute_wait(
    target_name,
    packet_name,
    item_name,
    value_type,
    comparison_to_eval,
    timeout,
    polling_rate,
):
    start_time = time.time()
    success, value = openc3_script_wait_implementation(
        target_name,
        packet_name,
        item_name,
        value_type,
        comparison_to_eval,
        timeout,
        polling_rate,
    )
    time_float = time.time() - start_time
    wait_str = "WAIT: {:s} {:s}".format(
        _upcase(target_name, packet_name, item_name), comparison_to_eval
    )
    value_str = "with value == {:s} after waiting {:g} seconds".format(
        str(value), time_float
    )
    if success:
        Logger.info("{:s} success {:s}".format(wait_str, value_str))
    else:
        Logger.warning("{:s} failed {:s}".format(wait_str, value_str))


def wait_process_args(args, function_name, value_type):
    time_float = None

    length = len(args)
    if length == 0:
        start_time = time.time()
        cosmos_script_sleep()
        time_float = time.time() - start_time
        Logger.info(
            "WAIT: Indefinite for actual time of {:g} seconds".format(time_float)
        )

    elif length == 1:
        try:
            value = float(args[0])
        except ValueError:
            raise RuntimeError("Non-numeric wait time specified")

        start_time = time.time()
        cosmos_script_sleep(value)
        time_float = time.time() - start_time
        Logger.info(
            "WAIT: {:g} seconds with actual time of {:g} seconds".format(
                value, time_float
            )
        )

    elif length == 2 or length == 3:
        (
            target_name,
            packet_name,
            item_name,
            comparison_to_eval,
        ) = extract.extract_fields_from_check_text(args[0])
        timeout = args[1]
        if length == 3:
            polling_rate = args[2]
        else:
            polling_rate = DEFAULT_TLM_POLLING_RATE
        _execute_wait(
            target_name,
            packet_name,
            item_name,
            value_type,
            comparison_to_eval,
            timeout,
            polling_rate,
        )

    elif length == 5 or length == 6:
        target_name = args[0]
        packet_name = args[1]
        item_name = args[2]
        comparison_to_eval = args[3]
        timeout = args[4]
        if length == 6:
            polling_rate = args[5]
        else:
            polling_rate = DEFAULT_TLM_POLLING_RATE
        _execute_wait(
            target_name,
            packet_name,
            item_name,
            value_type,
            comparison_to_eval,
            timeout,
            polling_rate,
        )
    else:
        # Invalid number of arguments
        raise RuntimeError(
            "ERROR: Invalid number of arguments ({:d}) passed to {:s}()".format(
                length, function_name
            )
        )
    return time_float


def wait_tolerance_process_args(args, function_name):
    length = len(args)
    if length == 4 or length == 5:
        target_name, packet_name, item_name = extract.extract_fields_from_tlm_text(
            args[0]
        )
        expected_value = args[1]
        tolerance = abs(args[2])
        timeout = args[3]
        if length == 5:
            polling_rate = args[4]
        else:
            polling_rate = DEFAULT_TLM_POLLING_RATE
    elif length == 6 or length == 7:
        target_name = args[0]
        packet_name = args[1]
        item_name = args[2]
        expected_value = args[3]
        tolerance = abs(args[4])
        timeout = args[5]
        if length == 7:
            polling_rate = args[6]
        else:
            polling_rate = DEFAULT_TLM_POLLING_RATE
    else:
        # Invalid number of arguments
        raise RuntimeError(
            "ERROR: Invalid number of arguments ({:d}) passed to {:s}()".format(
                length, function_name
            )
        )
    return [
        target_name,
        packet_name,
        item_name,
        expected_value,
        tolerance,
        timeout,
        polling_rate,
    ]


def array_tolerance_process_args(array_size, expected_value, tolerance, function_name):
    """
    When testing an array with a tolerance, the expected value and tolerance
    can both be supplied as either an array or a single value.  If a single
    value is passed in, that value will be used for all array elements.
    """
    if isinstance(expected_value, list):
        if array_size != len(expected_value):
            raise RuntimeError(
                "ERROR: Invalid array size for expected_value passed to {:s}()".format(
                    function_name
                )
            )
    else:
        expected_value = [expected_value] * array_size
    if isinstance(tolerance, list):
        if array_size != len(tolerance):
            raise RuntimeError(
                "ERROR: Invalid array size for tolerance passed to {:s}()".format(
                    function_name
                )
            )
    else:
        tolerance = [tolerance] * array_size
    return [expected_value, tolerance]


def wait_check_process_args(args, function_name):
    length = len(args)
    if length == 2 or length == 3:
        (
            target_name,
            packet_name,
            item_name,
            comparison_to_eval,
        ) = extract.extract_fields_from_check_text(args[0])
        timeout = args[1]
        if length == 3:
            polling_rate = args[2]
        else:
            polling_rate = DEFAULT_TLM_POLLING_RATE
    elif length == 5 or length == 6:
        target_name = args[0]
        packet_name = args[1]
        item_name = args[2]
        comparison_to_eval = args[3]
        timeout = args[4]
        if length == 6:
            polling_rate = args[5]
        else:
            polling_rate = DEFAULT_TLM_POLLING_RATE
    else:
        # Invalid number of arguments
        raise RuntimeError(
            "ERROR: Invalid number of arguments ({:d}) passed to {:s}()".format(
                length, function_name
            )
        )
    return [
        target_name,
        packet_name,
        item_name,
        comparison_to_eval,
        timeout,
        polling_rate,
    ]


def cosmos_script_sleep(sleep_time=None):
    """sleep in a script - returns true if canceled mid sleep"""
    if sleep_time != None:
        time.sleep(sleep_time)
    else:
        input("Infinite Wait - Press Enter to Continue: ")
    return False


def _cosmos_script_wait_implementation(
    target_name, packet_name, item_name, value_type, timeout, polling_rate, exp_to_eval
):
    end_time = time.time() + timeout

    while True:
        work_start = time.time()
        value = telemetry.tlm_variable(target_name, packet_name, item_name, value_type)
        if eval(exp_to_eval):
            return [True, value]
        if time.time() >= end_time:
            break

        delta = time.time() - work_start
        sleep_time = polling_rate - delta
        end_delta = end_time - time.time()
        if end_delta < sleep_time:
            sleep_time = end_delta
        if sleep_time < 0:
            sleep_time = 0
        canceled = cosmos_script_sleep(sleep_time)

        if canceled:
            value = telemetry.tlm_variable(
                target_name, packet_name, item_name, value_type
            )
            if eval(exp_to_eval):
                return [True, value]
            else:
                return [False, value]

    return [False, value]


# Wait for a converted telemetry item to pass a comparison
def openc3_script_wait_implementation(
    target_name,
    packet_name,
    item_name,
    value_type,
    comparison_to_eval,
    timeout,
    polling_rate=DEFAULT_TLM_POLLING_RATE,
):
    exp_to_eval = "value " + comparison_to_eval
    return _cosmos_script_wait_implementation(
        target_name,
        packet_name,
        item_name,
        value_type,
        timeout,
        polling_rate,
        exp_to_eval,
    )


def cosmos_script_wait_implementation_tolerance(
    target_name,
    packet_name,
    item_name,
    value_type,
    expected_value,
    tolerance,
    timeout,
    polling_rate=DEFAULT_TLM_POLLING_RATE,
):
    exp_to_eval = "(value >= ({:g} - {:g}) and value <= ({:g} + {:g}))".format(
        expected_value, abs(tolerance), abs(tolerance), expected_value
    )
    return _cosmos_script_wait_implementation(
        target_name,
        packet_name,
        item_name,
        value_type,
        timeout,
        polling_rate,
        exp_to_eval,
    )


def cosmos_script_wait_implementation_array_tolerance(
    array_size,
    target_name,
    packet_name,
    item_name,
    value_type,
    expected_value,
    tolerance,
    timeout,
    polling_rate=DEFAULT_TLM_POLLING_RATE,
):
    statements = []
    for i in range(array_size):
        statements.append(
            "(value >= ({:g} - {:g}) and value <= ({:g} + {:g}))".format(
                expected_value[i],
                abs(tolerance[i]),
                abs(tolerance[i]),
                expected_value[i],
            )
        )
    exp_to_eval = " and ".join(statements)
    return _cosmos_script_wait_implementation(
        target_name,
        packet_name,
        item_name,
        value_type,
        timeout,
        polling_rate,
        exp_to_eval,
    )


def cosmos_script_wait_implementation_expression(
    exp_to_eval, timeout, polling_rate, locals=None
):
    """Wait on an expression to be true."""
    end_time = time.time() + timeout
    # ~ context = ScriptRunnerFrame.instance.script_binding if !context and defined? ScriptRunnerFrame and ScriptRunnerFrame.instance

    while True:
        work_start = time.time()
        if eval(exp_to_eval, locals):
            return True
        if time.time() >= end_time:
            break

        delta = time.time() - work_start
        sleep_time = polling_rate - delta
        end_delta = end_time - time.time()
        if end_delta < sleep_time:
            sleep_time = end_delta
        if sleep_time < 0:
            sleep_time = 0
        canceled = cosmos_script_sleep(sleep_time)

        if canceled:
            if eval(exp_to_eval, locals):
                return True
            else:
                return None

    return None


# TODO: scope
def check_eval(target_name, packet_name, item_name, comparison_to_eval, value):
    if not comparison_to_eval.isascii():
        raise "Invalid comparison to non-ascii value"
    string = "value " + comparison_to_eval
    check_str = "CHECK: {:s} {:s}".format(
        _upcase(target_name, packet_name, item_name), comparison_to_eval
    )
    # Show user the check against a quoted string
    # Note: We have to preserve the original 'value' variable because we're going to eval against it
    if isinstance(value, str):
        value_str = f"'{value}'"
    else:
        value_str = value
    with_value = f"with value == {value_str}"
    try:
        if eval(string):
            Logger.info("{:s} success {:s}".format(check_str, with_value))
        else:
            message = "{:s} failed {:s}".format(check_str, with_value)
            raise CheckError(message)
            if DISCONNECT:
                pass
            # TODO Handle disconnect
    except NameError as error:
        parts = error.args[0].split("'")
        new_error = NameError(
            f"Uninitialized constant {parts[1]}. Did you mean '{parts[1]}' as a string?"
        )
        raise new_error from error
