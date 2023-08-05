#!/usr/bin/env python3

# Copyright 2023 OpenC3, Inc.
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

import time


# Defined here but overriden by running_script.py
def openc3_script_sleep(sleep_time=None):
    time.sleep(sleep_time)


# def prompt_for_hazardous(target_name, cmd_name, hazardous_description):
#     message = f"Warning: Command {target_name} {cmd_name} is Hazardous. "
#     if hazardous_description:
#         message += f"\n{hazardous_description}\n"
#     message += f"Send? (y): "
#     print(message)
#     return True


def prompt_for_hazardous(target_name, cmd_name, hazardous_description):
    """ """
    message_list = [f"Warning: Command {target_name} {cmd_name} is Hazardous. "]
    if hazardous_description:
        message_list.append(hazardous_description)
    message_list.append("Send? (y/N): ")
    answer = input("\n".join(message_list))
    try:
        return answer.lower()[0] == "y"
    except IndexError:
        return False
