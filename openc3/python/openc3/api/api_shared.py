# Copyright 2024 OpenC3, Inc.
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

import sys
import time
from openc3.api.tlm_api import tlm
from openc3.script.exceptions import CheckError
from openc3.utilities.extract import (
    extract_fields_from_check_text,
    extract_fields_from_tlm_text,
)
from openc3.environment import OPENC3_SCOPE

DEFAULT_TLM_POLLING_RATE = 0.25

# NOTE: The formatting applied throughout uses :.Xf meaning X decimal points
# This allows extremely small wait times to simply be displayed 0.000.
# Without the 'f' :.X means display X significant figures


def check(*args, type="CONVERTED", scope="DEFAULT"):
    """Check the converted value of a telmetry item against a condition
    Always print the value of the telemetry item to STDOUT
    If the condition check fails, raise an error
    Supports two signatures:
    check(target_name, packet_name, item_name, comparison_to_eval)
    or
    check('target_name packet_name item_name > 1')
    """
    return _check(*args, type=type, scope=scope)


def check_raw(*args, scope="DEFAULT"):
    """Check the raw value of a telmetry item against a condition
    Always print the value of the telemetry item to STDOUT
    If the condition check fails, raise an error
    Supports two signatures:
    check(target_name, packet_name, item_name, comparison_to_eval)
    or
    check('target_name packet_name item_name > 1')
    """
    return _check(*args, type="RAW", scope=scope)


def check_formatted(*args, scope="DEFAULT"):
    """Check the formatted value of a telmetry item against a condition
    Always print the value of the telemetry item to STDOUT
    If the condition check fails, raise an error
    Supports two signatures:
    check(target_name, packet_name, item_name, comparison_to_eval)
    or
    check('target_name packet_name item_name > 1')
    """
    return _check(*args, type="FORMATTED", scope=scope)


def check_with_units(*args, scope="DEFAULT"):
    """Check the formatted with units value of a telmetry item against a condition
    Always print the value of the telemetry item to STDOUT
    If the condition check fails, raise an error
    Supports two signatures:
    check(target_name, packet_name, item_name, comparison_to_eval)
    or
    check('target_name packet_name item_name > 1')
    """
    return _check(*args, type="WITH_UNITS", scope=scope)


def check_exception(method_name, *args, **kwargs):
    """Executes the passed method and expects an exception to be raised.
    Raises a CheckError if an Exception is not raised.
    Usage: check_exception(method_name, method_params}"""
    try:
        method = method_name
        orig_kwargs = kwargs.copy()
        if "scope" not in kwargs:
            kwargs["scope"] = OPENC3_SCOPE
        getattr(sys.modules[__name__], method_name)(*args, **kwargs)
        method = f"{method_name}({', '.join(args)}"
        if orig_kwargs:
            method += f", {orig_kwargs}"
        method += ")"
    except Exception as error:
        print(f"CHECK: {method} raised {repr(error)}")
    else:
        raise CheckError(f"{method} should have raised an exception but did not.")


def check_tolerance(*args, type="CONVERTED", scope=OPENC3_SCOPE):
    """Check the converted value of a telmetry item against an expected value with a tolerance
    Always print the value of the telemetry item to STDOUT
    If the condition check fails, raise an error
    Supports two signatures:
    check_tolerance(target_name, packet_name, item_name, expected_value, tolerance)
    or
    check_tolerance('target_name packet_name item_name', expected_value, tolerance)
    """
    if type not in ["RAW", "CONVERTED"]:
        raise RuntimeError(f"Invalid type '{type}' for check_tolerance")

    (
        target_name,
        packet_name,
        item_name,
        expected_value,
        tolerance,
    ) = _check_tolerance_process_args(args)

    value = tlm(target_name, packet_name, item_name, type=type, scope=scope)
    if isinstance(value, list):
        expected_value, tolerance = _array_tolerance_process_args(
            len(value), expected_value, tolerance, "check_tolerance"
        )

        message = ""
        all_checks_ok = True
        for i in range(len(value)):
            range_bottom = expected_value[i] - tolerance[i]
            range_top = expected_value[i] + tolerance[i]
            check_str = f"CHECK: {_upcase(target_name, packet_name, item_name)}[{i}]"
            range_str = f"range {_frange(range_bottom)} to {_frange(range_top)} with value == {value[i]}"
            if value[i] >= range_bottom and value[i] <= range_top:
                message += f"{check_str} was within {range_str}\n"
            else:
                message += f"{check_str} failed to be within {range_str}\n"
                all_checks_ok = False

        if all_checks_ok:
            print(message)
        else:
            raise CheckError(message)
    else:
        range_bottom = expected_value - tolerance
        range_top = expected_value + tolerance
        check_str = f"CHECK: {_upcase(target_name, packet_name, item_name)}"
        range_str = f"range {_frange(range_bottom)} to {_frange(range_top)} with value == {value}"
        if value >= range_bottom and value <= range_top:
            print(f"{check_str} was within {range_str}")
        else:
            message = f"{check_str} failed to be within {range_str}"
            raise CheckError(message)


def check_expression(exp_to_eval, globals=None, locals=None):
    """Check to see if an expression is true without waiting.  If the expression
    is not true, the script will pause."""
    success = _openc3_script_wait_expression(exp_to_eval, 0, DEFAULT_TLM_POLLING_RATE, globals, locals)
    if success:
        print(f"CHECK: {exp_to_eval} is TRUE")
    else:
        message = f"CHECK: {exp_to_eval} is FALSE"
        raise CheckError(message)


def wait(*args, type="CONVERTED", quiet=False, scope=OPENC3_SCOPE):
    """Wait on an expression to be true.  On a timeout, the script will continue.
    Supports multiple signatures:
    wait(time)
    wait('target_name packet_name item_name > 1', timeout, polling_rate)
    wait('target_name', 'packet_name', 'item_name', comparison_to_eval, timeout, polling_rate)
    """
    time_diff = None

    match len(args):
        # wait() # indefinitely until they click Go
        case 0:
            start_time = time.time()
            openc3_script_sleep()
            time_diff = time.time() - start_time
            if not quiet:
                print(f"WAIT: Indefinite for actual time of {time_diff:.3f} seconds")
            return time_diff

        # wait(5) # absolute wait time
        case 1:
            try:
                value = float(args[0])
            except ValueError:
                raise RuntimeError("Non-numeric wait time specified")

            start_time = time.time()
            openc3_script_sleep(value)
            time_diff = time.time() - start_time
            if not quiet:
                print(f"WAIT: {value} seconds with actual time of {time_diff:.3f} seconds")
            return time_diff

        # wait('target_name packet_name item_name > 1', timeout, polling_rate) # polling_rate is optional
        case 2 | 3:
            (
                target_name,
                packet_name,
                item_name,
                comparison_to_eval,
            ) = extract_fields_from_check_text(args[0])
            timeout = args[1]
            if len(args) == 3:
                polling_rate = args[2]
            else:
                polling_rate = DEFAULT_TLM_POLLING_RATE
            return _execute_wait(
                target_name,
                packet_name,
                item_name,
                type,
                comparison_to_eval,
                timeout,
                polling_rate,
                quiet,
                scope,
            )

        # wait('target_name', 'packet_name', 'item_name', comparison_to_eval, timeout, polling_rate) # polling_rate is optional
        case 5 | 6:
            target_name = args[0]
            packet_name = args[1]
            item_name = args[2]
            comparison_to_eval = args[3]
            timeout = args[4]
            if len(args) == 6:
                polling_rate = args[5]
            else:
                polling_rate = DEFAULT_TLM_POLLING_RATE
            return _execute_wait(
                target_name,
                packet_name,
                item_name,
                type,
                comparison_to_eval,
                timeout,
                polling_rate,
                quiet,
                scope,
            )
        case _:
            # Invalid number of arguments
            raise RuntimeError(f"ERROR: Invalid number of arguments ({len(args)}) passed to wait()")


def wait_tolerance(*args, type="CONVERTED", quiet=False, scope=OPENC3_SCOPE):
    """Wait on an expression to be true.  On a timeout, the script will continue.
    Supports multiple signatures:
    wait_tolerance('target_name packet_name item_name', expected_value, tolerance, timeout, polling_rate)
    wait_tolerance('target_name', 'packet_name', 'item_name', expected_value, tolerance, timeout, polling_rate)
    """
    if type not in ["RAW", "CONVERTED"]:
        raise RuntimeError(f"Invalid type '{type}' for wait_tolerance")

    (
        target_name,
        packet_name,
        item_name,
        expected_value,
        tolerance,
        timeout,
        polling_rate,
    ) = _wait_tolerance_process_args(args, "wait_tolerance")
    start_time = time.time()
    value = tlm(target_name, packet_name, item_name, type=type, scope=scope)
    if isinstance(value, list):
        expected_value, tolerance = _array_tolerance_process_args(
            len(value), expected_value, tolerance, "wait_tolerance"
        )
        success, value = _openc3_script_wait_array_tolerance(
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
        time_diff = time.time() - start_time

        message = ""
        for i in range(0, len(value)):
            range_bottom = expected_value[i] - tolerance[i]
            range_top = expected_value[i] + tolerance[i]
            check_str = f"WAIT: {_upcase(target_name, packet_name, item_name)}[{i}]"
            range_str = f"range {_frange(range_bottom)} to {_frange(range_top)} with value == {value[i]} after waiting {time_diff:.3f} seconds"
            if value[i] >= range_bottom and value[i] <= range_top:
                message += f"{check_str} was within {range_str}\n"
            else:
                message += f"{check_str} failed to be within {range_str}\n"

        if not quiet:
            if success:
                print(message)
            else:
                print(f"WARN: {message}")
    else:
        success, value = _openc3_script_wait_tolerance(
            target_name,
            packet_name,
            item_name,
            type,
            expected_value,
            tolerance,
            timeout,
            polling_rate,
        )
        time_diff = time.time() - start_time
        range_bottom = expected_value - tolerance
        range_top = expected_value + tolerance
        wait_str = f"WAIT: {_upcase(target_name, packet_name, item_name)}"
        range_str = f"range {_frange(range_bottom)} to {_frange(range_top)} with value == {value} after waiting {time_diff:.3f} seconds"
        if not quiet:
            if success:
                print(f"{wait_str} was within {range_str}")
            else:
                print(f"WARN: {wait_str} failed to be within {range_str}")
    return success


def wait_expression(
    exp_to_eval,
    timeout,
    polling_rate=DEFAULT_TLM_POLLING_RATE,
    globals=None,
    locals=None,
    quiet=False,
):
    """Wait on a custom expression to be true"""
    start_time = time.time()
    success = _openc3_script_wait_expression(exp_to_eval, timeout, polling_rate, globals, locals)
    time_diff = time.time() - start_time
    if not quiet:
        if success:
            print(f"WAIT: {exp_to_eval} is TRUE after waiting {time_diff:.3f} seconds")
        else:
            print(f"WARN: WAIT: {exp_to_eval} is FALSE after waiting {time_diff:.3f} seconds")
    return success


def wait_check(*args, type="CONVERTED", scope=OPENC3_SCOPE):
    """Wait for the converted value of a telmetry item against a condition or for a timeout
    and then check against the condition
    Supports two signatures:
    wait_check(target_name, packet_name, item_name, comparison_to_eval, timeout, polling_rate)
    or
    wait_check('target_name packet_name item_name > 1', timeout, polling_rate)"""
    (
        target_name,
        packet_name,
        item_name,
        comparison_to_eval,
        timeout,
        polling_rate,
    ) = _wait_check_process_args(args)
    start_time = time.time()
    success, value = _openc3_script_wait_value(
        target_name,
        packet_name,
        item_name,
        type,
        comparison_to_eval,
        timeout,
        polling_rate,
    )
    if isinstance(value, str):
        value = f"'{value}'"  # Show user the check against a quoted string
    time_diff = time.time() - start_time
    check_str = f"CHECK: {_upcase(target_name, packet_name, item_name)}"
    if comparison_to_eval:
        check_str += f" {comparison_to_eval}"
    with_value_str = f"with value == {value} after waiting {time_diff:.3f} seconds"
    if success:
        print(f"{check_str} success {with_value_str}")
    else:
        message = f"{check_str} failed {with_value_str}"
        raise CheckError(message)
    return time_diff


def wait_check_tolerance(*args, type="CONVERTED", scope=OPENC3_SCOPE):
    """Wait for the value of a telmetry item to be within a tolerance of a value
    and then check against the condition.
    Supports two signatures:
    wait_check_tolerance('target_name packet_name item_name', expected_value, tolerance, timeout, polling_rate)
    or
    wait_check_tolerance('target_name', 'packet_name', 'item_name', expected_value, tolerance, timeout, polling_rate)
    """
    if type not in ["RAW", "CONVERTED"]:
        raise RuntimeError(f"Invalid type '{type}' for wait_check_tolerance")

    (
        target_name,
        packet_name,
        item_name,
        expected_value,
        tolerance,
        timeout,
        polling_rate,
    ) = _wait_tolerance_process_args(args, "wait_check_tolerance")
    start_time = time.time()
    value = tlm(target_name, packet_name, item_name, type=type, scope=scope)
    if isinstance(value, list):
        expected_value, tolerance = _array_tolerance_process_args(
            len(value), expected_value, tolerance, "wait_check_tolerance"
        )
        success, value = _openc3_script_wait_array_tolerance(
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
        time_diff = time.time() - start_time

        message = ""
        for i in range(0, len(value)):
            range_bottom = expected_value[i] - tolerance[i]
            range_top = expected_value[i] + tolerance[i]
            check_str = f"CHECK: {_upcase(target_name, packet_name, item_name)}[{i}]"
            range_str = f"range {_frange(range_bottom)} to {_frange(range_top)} with value == {value[i]} after waiting {time_diff:.3f} seconds"
            if value[i] >= range_bottom and value[i] <= range_top:
                message += f"{check_str} was within {range_str}\n"
            else:
                message += f"{check_str} failed to be within {range_str}\n"

        if success:
            print(message)
        else:
            raise CheckError(message)
    else:
        success, value = _openc3_script_wait_tolerance(
            target_name,
            packet_name,
            item_name,
            type,
            expected_value,
            tolerance,
            timeout,
            polling_rate,
            scope,
        )
        time_diff = time.time() - start_time
        range_bottom = expected_value - tolerance
        range_top = expected_value + tolerance
        check_str = f"CHECK: {_upcase(target_name, packet_name, item_name)}"
        range_str = f"range {_frange(range_bottom)} to {_frange(range_top)} with value == {value} after waiting {time_diff:.3f} seconds"
        if success:
            print(f"{check_str} was within {range_str}")
        else:
            message = f"{check_str} failed to be within {range_str}"
            raise CheckError(message)
    return time_diff


def wait_check_expression(exp_to_eval, timeout, polling_rate=DEFAULT_TLM_POLLING_RATE, globals=None, locals=None):
    """Wait on an expression to be true.  On a timeout, the script will pause"""
    start_time = time.time()
    success = _openc3_script_wait_expression(exp_to_eval, timeout, polling_rate, globals, locals)
    time_diff = time.time() - start_time
    if success:
        print(f"CHECK: {exp_to_eval} is TRUE after waiting {time_diff:.3f} seconds")
    else:
        message = f"CHECK: {exp_to_eval} is FALSE after waiting {time_diff:.3f} seconds"
        raise CheckError(message)
    return time_diff


def wait_packet(
    target_name,
    packet_name,
    num_packets,
    timeout,
    polling_rate=DEFAULT_TLM_POLLING_RATE,
    quiet=False,
    scope=OPENC3_SCOPE,
):
    success, _ = _wait_packet(
        False,
        target_name,
        packet_name,
        num_packets,
        timeout,
        polling_rate,
        quiet,
        scope,
    )
    return success


def wait_check_packet(
    target_name,
    packet_name,
    num_packets,
    timeout,
    polling_rate=DEFAULT_TLM_POLLING_RATE,
    quiet=False,
    scope=OPENC3_SCOPE,
):
    """Wait for a telemetry packet to be received a certain number of times or timeout and raise an error"""
    _, time_diff = _wait_packet(True, target_name, packet_name, num_packets, timeout, polling_rate, quiet, scope)
    return time_diff


###########################################################################
# Private implementation details
###########################################################################


def openc3_script_sleep(sleep_time=None):
    if sleep_time:
        time.sleep(float(sleep_time))
    else:
        input("Press any key to continue...")


def _upcase(target_name, packet_name, item_name):
    """Creates a string with the parameters upcased"""
    return f"{target_name.upper()} {packet_name.upper()} {item_name.upper()}"


def _check(*args, type="CONVERTED", scope=OPENC3_SCOPE):
    """Implementation of the various check commands. It yields back to the
    caller to allow the return of the value through various telemetry calls.
    This method should not be called directly by application code."""
    target_name, packet_name, item_name, comparison_to_eval = _check_process_args(args, "check")
    value = tlm(target_name, packet_name, item_name, type=type, scope=scope)
    if comparison_to_eval:
        return _check_eval(target_name, packet_name, item_name, comparison_to_eval, value)
    else:
        print(f"CHECK: {_upcase(target_name, packet_name, item_name)} == {value}")


def _check_process_args(args, method_name):
    match len(args):
        case 1:
            (
                target_name,
                packet_name,
                item_name,
                comparison_to_eval,
            ) = extract_fields_from_check_text(args[0])
        case 3:
            target_name = args[0]
            packet_name = args[1]
            item_name = args[2]
            comparison_to_eval = None
        case 4:
            target_name = args[0]
            packet_name = args[1]
            item_name = args[2]
            comparison_to_eval = args[3]
        case _:
            # Invalid number of arguments
            raise RuntimeError(f"ERROR: Invalid number of arguments ({len(args)}) passed to {method_name}()")
    if comparison_to_eval and not comparison_to_eval.isascii():
        raise RuntimeError(f"ERROR: Invalid comparison to non-ascii value: {comparison_to_eval}")
    return target_name, packet_name, item_name, comparison_to_eval


def _check_tolerance_process_args(args):
    length = len(args)
    if length == 3:
        target_name, packet_name, item_name = extract_fields_from_tlm_text(args[0])
        expected_value = args[1]
        if isinstance(args[2], list):
            tolerance = [abs(x) for x in args[2]]
        else:
            tolerance = abs(args[2])
    elif length == 5:
        target_name = args[0]
        packet_name = args[1]
        item_name = args[2]
        expected_value = args[3]
        if isinstance(args[4], list):
            tolerance = [abs(x) for x in args[4]]
        else:
            tolerance = abs(args[4])
    else:
        # Invalid number of arguments
        raise RuntimeError(f"ERROR: Invalid number of arguments ({length}) passed to check_tolerance()")
    return target_name, packet_name, item_name, expected_value, tolerance


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
    initial_count = tlm(target_name, packet_name, "RECEIVED_COUNT", scope=scope)
    # If the packet has not been received the initial_count could be None
    if initial_count is None:
        initial_count = 0
    start_time = time.time()
    success, value = _openc3_script_wait_value(
        target_name,
        packet_name,
        "RECEIVED_COUNT",
        "CONVERTED",
        f">= {initial_count + num_packets}",
        timeout,
        polling_rate,
        scope,
    )
    # If the packet has not been received the value could be None
    if not value:
        value = 0
    time_diff = time.time() - start_time
    if success:
        if not quiet:
            print(
                f"{type}: {target_name.upper()} {packet_name.upper()} received {value - initial_count} times after waiting {time_diff:.3f} seconds"
            )
    else:
        message = f"{type}: {target_name.upper()} {packet_name.upper()} expected to be received {num_packets} times but only received {value - initial_count} times after waiting {time_diff:.3f} seconds"
        if check:
            raise CheckError(message)
        elif not quiet:
            print(f"WARN: {message}")
    return success, time_diff


def _execute_wait(
    target_name,
    packet_name,
    item_name,
    value_type,
    comparison_to_eval,
    timeout,
    polling_rate,
    quiet,
    scope,
):
    start_time = time.time()
    success, value = _openc3_script_wait_value(
        target_name,
        packet_name,
        item_name,
        value_type,
        comparison_to_eval,
        timeout,
        polling_rate,
        scope,
    )
    if isinstance(value, str):
        value = f"'{value}'"  # Show user the check against a quoted string
    time_diff = time.time() - start_time
    wait_str = f"WAIT: {_upcase(target_name, packet_name, item_name)} {comparison_to_eval}"
    value_str = f"with value == {value} after waiting {time_diff:.3f} seconds"
    if not quiet:
        if success:
            print(f"{wait_str} success {value_str}")
        else:
            print(f"WARN: {wait_str} failed {value_str}")
    return success


def _wait_tolerance_process_args(args, function_name):
    length = len(args)
    if length == 4 or length == 5:
        target_name, packet_name, item_name = extract_fields_from_tlm_text(args[0])
        expected_value = args[1]
        if isinstance(args[2], list):
            tolerance = [abs(x) for x in args[2]]
        else:
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
        if isinstance(args[4], list):
            tolerance = [abs(x) for x in args[4]]
        else:
            tolerance = abs(args[4])
        timeout = args[5]
        if length == 7:
            polling_rate = args[6]
        else:
            polling_rate = DEFAULT_TLM_POLLING_RATE
    else:
        # Invalid number of arguments
        raise RuntimeError(f"ERROR: Invalid number of arguments ({length}) passed to {function_name}()")
    return (
        target_name,
        packet_name,
        item_name,
        expected_value,
        tolerance,
        timeout,
        polling_rate,
    )


def _array_tolerance_process_args(array_size, expected_value, tolerance, function_name):
    """
    When testing an array with a tolerance, the expected value and tolerance
    can both be supplied as either an array or a single value.  If a single
    value is passed in, that value will be used for all array elements.
    """
    if isinstance(expected_value, list):
        if array_size != len(expected_value):
            raise RuntimeError(f"ERROR: Invalid array size for expected_value passed to {function_name}()")
    else:
        expected_value = [expected_value] * array_size
    if isinstance(tolerance, list):
        if array_size != len(tolerance):
            raise RuntimeError(f"ERROR: Invalid array size for tolerance passed to {function_name}()")
    else:
        tolerance = [tolerance] * array_size
    return expected_value, tolerance


def _wait_check_process_args(args):
    length = len(args)
    if length == 2 or length == 3:
        (
            target_name,
            packet_name,
            item_name,
            comparison_to_eval,
        ) = extract_fields_from_check_text(args[0])
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
        raise RuntimeError(f"ERROR: Invalid number of arguments ({len(args)}) passed to wait_check()")
    return (
        target_name,
        packet_name,
        item_name,
        comparison_to_eval,
        timeout,
        polling_rate,
    )


def _openc3_script_wait(
    target_name,
    packet_name,
    item_name,
    value_type,
    timeout,
    polling_rate,
    exp_to_eval,
    scope,
):
    value = None
    end_time = time.time() + timeout
    if exp_to_eval and not exp_to_eval.isascii():
        raise RuntimeError("ERROR: Invalid comparison to non-ascii value")

    try:
        while True:
            work_start = time.time()
            value = tlm(target_name, packet_name, item_name, type=value_type, scope=scope)
            try:
                if eval(exp_to_eval):
                    return True, value
            # We get TypeError when trying to eval None >= 0 (for example)
            # In this case we just continue and see if eventually we get a good value from tlm()
            except TypeError:
                pass
            if time.time() >= end_time:
                break

            delta = time.time() - work_start
            sleep_time = polling_rate - delta
            end_delta = end_time - time.time()
            if end_delta < sleep_time:
                sleep_time = end_delta
            if sleep_time < 0:
                sleep_time = 0
            canceled = openc3_script_sleep(sleep_time)

            if canceled:
                value = tlm(target_name, packet_name, item_name, type=value_type, scope=scope)
                try:
                    if eval(exp_to_eval):
                        return True, value
                    else:
                        return False, value
                # We get TypeError when trying to eval None >= 0 (for example)
                except TypeError:
                    return False, value

    except NameError as error:
        parts = error.args[0].split("'")
        new_error = NameError(f"Uninitialized constant {parts[1]}. Did you mean '{parts[1]}' as a string?")
        raise new_error from error

    return False, value


# Wait for a converted telemetry item to pass a comparison
def _openc3_script_wait_value(
    target_name,
    packet_name,
    item_name,
    value_type,
    comparison_to_eval,
    timeout,
    polling_rate=DEFAULT_TLM_POLLING_RATE,
    scope=OPENC3_SCOPE,
):
    if comparison_to_eval:
        exp_to_eval = "value " + comparison_to_eval
    else:
        exp_to_eval = None
    return _openc3_script_wait(
        target_name,
        packet_name,
        item_name,
        value_type,
        timeout,
        polling_rate,
        exp_to_eval,
        scope,
    )


def _openc3_script_wait_tolerance(
    target_name,
    packet_name,
    item_name,
    value_type,
    expected_value,
    tolerance,
    timeout,
    polling_rate=DEFAULT_TLM_POLLING_RATE,
    scope=OPENC3_SCOPE,
):
    exp_to_eval = f"(value >= ({expected_value} - {abs(tolerance)}) and value <= ({expected_value} + {abs(tolerance)}))"
    return _openc3_script_wait(
        target_name,
        packet_name,
        item_name,
        value_type,
        timeout,
        polling_rate,
        exp_to_eval,
        scope,
    )


def _openc3_script_wait_array_tolerance(
    array_size,
    target_name,
    packet_name,
    item_name,
    value_type,
    expected_value,
    tolerance,
    timeout,
    polling_rate=DEFAULT_TLM_POLLING_RATE,
    scope=OPENC3_SCOPE,
):
    statements = []
    for i in range(array_size):
        statements.append(
            f"(value[{i}] >= ({expected_value[i]} - {abs(tolerance[i])}) and value[{i}] <= ({expected_value[i]} + {abs(tolerance[i])}))"
        )
    exp_to_eval = " and ".join(statements)
    return _openc3_script_wait(
        target_name,
        packet_name,
        item_name,
        value_type,
        timeout,
        polling_rate,
        exp_to_eval,
        scope,
    )


def _openc3_script_wait_expression(exp_to_eval, timeout, polling_rate, globals=None, locals=None):
    """Wait on an expression to be true."""
    end_time = time.time() + timeout
    if not exp_to_eval.isascii():
        raise RuntimeError(f"Invalid comparison to non-ascii value: {exp_to_eval}")

    try:
        while True:
            work_start = time.time()
            if eval(exp_to_eval, globals, locals):
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
            canceled = openc3_script_sleep(sleep_time)

            if canceled:
                if eval(exp_to_eval, globals, locals):
                    return True
                else:
                    return None
    except NameError as error:
        parts = error.args[0].split("'")
        new_error = NameError(f"Uninitialized constant {parts[1]}. Did you mean '{parts[1]}' as a string?")
        raise new_error from error

    return None


def _check_eval(target_name, packet_name, item_name, comparison_to_eval, value):
    string = "value " + comparison_to_eval
    check_str = f"CHECK: {_upcase(target_name, packet_name, item_name)} {comparison_to_eval}"
    # Show user the check against a quoted string
    # Note: We have to preserve the original 'value' variable because we're going to eval against it
    if isinstance(value, str):
        value_str = f"'{value}'"
    else:
        value_str = value
    with_value = f"with value == {value_str}"
    try:
        if eval(string):
            print(f"{check_str} success {with_value}")
        else:
            message = f"{check_str} failed {with_value}"
            raise CheckError(message)
    except NameError as error:
        parts = error.args[0].split("'")
        new_error = NameError(f"Uninitialized constant {parts[1]}. Did you mean '{parts[1]}' as a string?")
        raise new_error from error


def _frange(value):
    if isinstance(value, float):
        # Display at most 6 significant figures on a range value
        # This truncates float values like 1.6500000000000001 to simply 1.65
        return f"{value:.6}"
    else:
        return value


# Interesting formatter to a specific number of significant digits:
# https://stackoverflow.com/questions/3410976/how-to-round-a-number-to-significant-figures-in-python?rq=3
# def format(value, sigfigs=9):
#     if isinstance(value, float):
#         return "{:.{p}g}".format(float("{:.{p}g}".format(value, p=sigfigs)), p=sigfigs)
#     else:
#         return value
