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

# Enable and disable limits groups and watch their rollup in the LIMITS_GROUP
# packet of the target which defines each group. INST PAYLOAD nests INST TEMPS
# and INST GROUND. SYSTEM PAYLOAD nests the TEMPS and GROUND groups of INST and
# INST2 and also contains INST HEALTH_STATUS ZERO directly (see
# cmd_tlm/limits_groups.txt). See procedures/limits_groups.py in INST2 for the
# Python version.

# Each API worker caches packet definitions for up to 10s so limits_enabled?
# can briefly return the old value. Wait for it rather than checking once.
CACHE_SECONDS = 15

begin
  enable_limits_group('SYSTEM', 'PAYLOAD')
  enable_limits_group('INST', 'PAYLOAD')
  wait_check("SYSTEM LIMITS_GROUP PAYLOAD_ENABLED == 'TRUE'", 10)
  wait_check("INST LIMITS_GROUP TEMPS_ENABLED == 'TRUE'", 10)

  # cascade: false only changes the group itself and the items directly in it,
  # so ZERO but not the nested groups
  disable_limits_group('SYSTEM', 'PAYLOAD', cascade: false)
  wait_check_expression("limits_enabled?('INST HEALTH_STATUS ZERO') == false", CACHE_SECONDS)
  wait_check_expression("limits_enabled?('INST HEALTH_STATUS TEMP1') == true", CACHE_SECONDS)
  wait_check_expression("limits_enabled?('INST2 HEALTH_STATUS TEMP1') == true", CACHE_SECONDS)
  # SYSTEM PAYLOAD itself is disabled so it's DISABLED while its nested groups keep checking limits
  wait_check("SYSTEM LIMITS_GROUP PAYLOAD_ENABLED == 'FALSE'", 10)
  wait_check("SYSTEM LIMITS_GROUP PAYLOAD == 'DISABLED'", 10)
  check("INST LIMITS_GROUP TEMPS_ENABLED == 'TRUE'")
  check("INST LIMITS_GROUP TEMPS != 'DISABLED'")
  enable_limits_group('SYSTEM', 'PAYLOAD', cascade: false)
  wait_check_expression("limits_enabled?('INST HEALTH_STATUS ZERO') == true", CACHE_SECONDS)
  wait_check("SYSTEM LIMITS_GROUP PAYLOAD_ENABLED == 'TRUE'", 10)

  # INST PAYLOAD only contains nested groups. Without cascade only PAYLOAD itself is disabled.
  disable_limits_group('INST', 'PAYLOAD', cascade: false)
  wait_check("INST LIMITS_GROUP PAYLOAD == 'DISABLED'", 10)
  wait_check("INST LIMITS_GROUP PAYLOAD_ENABLED == 'FALSE'", 10)
  check("INST LIMITS_GROUP TEMPS_ENABLED == 'TRUE'")
  check("INST LIMITS_GROUP GROUND_ENABLED == 'TRUE'")
  wait_check_expression("limits_enabled?('INST HEALTH_STATUS TEMP1') == true", CACHE_SECONDS)
  enable_limits_group('INST', 'PAYLOAD', cascade: false)
  wait_check("INST LIMITS_GROUP PAYLOAD_ENABLED == 'TRUE'", 10)

  # A disabled group is DISABLED and makes the groups which contain it PARTIAL
  disable_limits_group('INST', 'TEMPS')
  wait_check_expression("limits_enabled?('INST HEALTH_STATUS TEMP1') == false", CACHE_SECONDS)
  wait_check("INST LIMITS_GROUP TEMPS_ENABLED == 'FALSE'", 10)
  wait_check("INST LIMITS_GROUP TEMPS == 'DISABLED'", 10)
  wait_check("INST LIMITS_GROUP PAYLOAD_ENABLED == 'PARTIAL'", 10)
  wait_check("SYSTEM LIMITS_GROUP PAYLOAD_ENABLED == 'PARTIAL'", 10)

  # Enabling SYSTEM PAYLOAD without cascade leaves INST TEMPS disabled
  enable_limits_group('SYSTEM', 'PAYLOAD', cascade: false)
  wait_check_expression("limits_enabled?('INST HEALTH_STATUS TEMP1') == false", CACHE_SECONDS)
  check("SYSTEM LIMITS_GROUP PAYLOAD_ENABLED == 'PARTIAL'")

  # By default the items of every nested group change too
  disable_limits_group('SYSTEM', 'PAYLOAD')
  wait_check_expression("limits_enabled?('INST HEALTH_STATUS ZERO') == false", CACHE_SECONDS)
  wait_check_expression("limits_enabled?('INST2 HEALTH_STATUS GROUND1STATUS') == false", CACHE_SECONDS)
  wait_check("SYSTEM LIMITS_GROUP PAYLOAD_ENABLED == 'FALSE'", 10)
  wait_check("SYSTEM LIMITS_GROUP PAYLOAD == 'DISABLED'", 10)
  wait_check("INST2 LIMITS_GROUP PAYLOAD == 'DISABLED'", 10)

  enable_limits_group('SYSTEM', 'PAYLOAD')
  wait_check_expression("limits_enabled?('INST HEALTH_STATUS TEMP1') == true", CACHE_SECONDS)
  wait_check("SYSTEM LIMITS_GROUP PAYLOAD_ENABLED == 'TRUE'", 10)
  wait_check("SYSTEM LIMITS_GROUP PAYLOAD != 'DISABLED'", 10)
ensure
  enable_limits_group('SYSTEM', 'PAYLOAD')
  enable_limits_group('INST', 'PAYLOAD')
end
