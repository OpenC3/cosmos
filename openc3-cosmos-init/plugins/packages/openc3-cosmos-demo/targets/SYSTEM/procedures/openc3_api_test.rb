# cmd
cmd("INST ABORT")
cmd("INST ARYCMD with ARRAY []")
cmd("INST CLEAR")
cmd("INST COLLECT with DURATION 1.0, TEMP 0.0, TYPE 'NORMAL'")
cmd("INST FLTCMD with FLOAT32 0.0, FLOAT64 0.0")
cmd("INST SETPARAMS with VALUE1 0, VALUE2 0, VALUE3 0, VALUE4 0, VALUE5 0")
cmd("INST SLRPNLDEPLOY")
cmd("INST SLRPNLRESET")
cmd("INST ASCIICMD with STRING 'ARM LASER'")

cmd("INST", "ABORT")
cmd("INST", "ARYCMD", "ARRAY" => [])
cmd("INST", "CLEAR")
cmd("INST", "COLLECT", "DURATION" => 1.0, "TEMP" => 0.0, "TYPE" => 'NORMAL')
cmd("INST", "FLTCMD", "FLOAT32" => 0.0, "FLOAT64" => 0.0)
cmd("INST", "SETPARAMS", "VALUE1" => 0, "VALUE2" => 0, "VALUE3" => 0, "VALUE4" => 0, "VALUE5" => 0)
cmd("INST", "SLRPNLDEPLOY")
cmd("INST", "SLRPNLRESET")
cmd("INST", "ASCIICMD", "STRING" => 'ARM LASER')

# cmd should fail
begin
  cmd("INST COLLECT with DURATION 11, TYPE 'NORMAL'")
rescue RuntimeError => e
  raise "Fail" if e.message != "Command parameter 'INST COLLECT DURATION' = 11 not in valid range of 0.0 to 10.0"
rescue
  raise "Fail"
end

cmd()
cmd("BOB")
cmd("BOB", "ABORT")
cmd("INST", "BOB")
cmd("INST", "ABORT", "BOB" => "BOB")
cmd("INST", "ABORT", "TED", "BOB" => "BOB")
cmd("BOB")
cmd("BOB ABORT")
cmd("INST BOB")

# cmd_no_range_check
cmd_no_range_check("INST ABORT")
cmd_no_range_check("INST ARYCMD with ARRAY []")
cmd_no_range_check("INST CLEAR")
cmd_no_range_check("INST COLLECT with DURATION 1.0, TEMP 0.0, TYPE 'NORMAL'")
cmd_no_range_check("INST FLTCMD with FLOAT32 0.0, FLOAT64 0.0")
cmd_no_range_check("INST SETPARAMS with VALUE1 0, VALUE2 0, VALUE3 0, VALUE4 0, VALUE5 0")
cmd_no_range_check("INST SLRPNLDEPLOY")
cmd_no_range_check("INST SLRPNLRESET")
cmd_no_range_check("INST ASCIICMD with STRING 'ARM LASER'")
cmd_no_range_check("INST COLLECT with DURATION 11, TYPE 'NORMAL'")

cmd_no_range_check("INST", "ABORT")
cmd_no_range_check("INST", "ARYCMD", "ARRAY" => [])
cmd_no_range_check("INST", "CLEAR")
cmd_no_range_check("INST", "COLLECT", "DURATION" => 1.0, "TEMP" => 0.0, "TYPE" => 'NORMAL')
cmd_no_range_check("INST", "FLTCMD", "FLOAT32" => 0.0, "FLOAT64" => 0.0)
cmd_no_range_check("INST", "SETPARAMS", "VALUE1" => 0, "VALUE2" => 0, "VALUE3" => 0, "VALUE4" => 0, "VALUE5" => 0)
cmd_no_range_check("INST", "SLRPNLDEPLOY")
cmd_no_range_check("INST", "SLRPNLRESET")
cmd_no_range_check("INST", "ASCIICMD", "STRING" => 'ARM LASER')
cmd_no_range_check("INST", "COLLECT", "DURATION" => 11, "TYPE" => 'NORMAL')

# cmd_no_range_check should fail
cmd_no_range_check()
cmd_no_range_check("BOB")
cmd_no_range_check("BOB", "ABORT")
cmd_no_range_check("INST", "BOB")
cmd_no_range_check("INST", "ABORT", "BOB" => "BOB")
cmd_no_range_check("INST", "ABORT", "TED", "BOB" => "BOB")
cmd_no_range_check("BOB")
cmd_no_range_check("BOB ABORT")
cmd_no_range_check("INST BOB")

# cmd_no_hazardous_check
cmd_no_hazardous_check("INST ABORT")
cmd_no_hazardous_check("INST ARYCMD with ARRAY []")
cmd_no_hazardous_check("INST CLEAR")
cmd_no_hazardous_check("INST COLLECT with DURATION 1.0, TEMP 0.0, TYPE 'NORMAL'")
cmd_no_hazardous_check("INST FLTCMD with FLOAT32 0.0, FLOAT64 0.0")
cmd_no_hazardous_check("INST SETPARAMS with VALUE1 0, VALUE2 0, VALUE3 0, VALUE4 0, VALUE5 0")
cmd_no_hazardous_check("INST SLRPNLDEPLOY")
cmd_no_hazardous_check("INST SLRPNLRESET")
cmd_no_hazardous_check("INST ASCIICMD with STRING 'ARM LASER'")

cmd_no_hazardous_check("INST", "ABORT")
cmd_no_hazardous_check("INST", "ARYCMD", "ARRAY" => [])
cmd_no_hazardous_check("INST", "CLEAR")
cmd_no_hazardous_check("INST", "COLLECT", "DURATION" => 1.0, "TEMP" => 0.0, "TYPE" => 'NORMAL')
cmd_no_hazardous_check("INST", "FLTCMD", "FLOAT32" => 0.0, "FLOAT64" => 0.0)
cmd_no_hazardous_check("INST", "SETPARAMS", "VALUE1" => 0, "VALUE2" => 0, "VALUE3" => 0, "VALUE4" => 0, "VALUE5" => 0)
cmd_no_hazardous_check("INST", "SLRPNLDEPLOY")
cmd_no_hazardous_check("INST", "SLRPNLRESET")
cmd_no_hazardous_check("INST", "ASCIICMD", "STRING" => 'ARM LASER')

# cmd_no_hazardous_check should fail
cmd_no_hazardous_check("INST COLLECT with DURATION 11, TYPE 'NORMAL'")
cmd_no_hazardous_check()
cmd_no_hazardous_check("BOB")
cmd_no_hazardous_check("BOB", "ABORT")
cmd_no_hazardous_check("INST", "BOB")
cmd_no_hazardous_check("INST", "ABORT", "BOB" => "BOB")
cmd_no_hazardous_check("INST", "ABORT", "TED", "BOB" => "BOB")
cmd_no_hazardous_check("BOB")
cmd_no_hazardous_check("BOB ABORT")
cmd_no_hazardous_check("INST BOB")

# cmd_no_checks
cmd_no_checks("INST ABORT")
cmd_no_checks("INST ARYCMD with ARRAY []")
cmd_no_checks("INST CLEAR")
cmd_no_checks("INST COLLECT with DURATION 1.0, TEMP 0.0, TYPE 'NORMAL'")
cmd_no_checks("INST FLTCMD with FLOAT32 0.0, FLOAT64 0.0")
cmd_no_checks("INST SETPARAMS with VALUE1 0, VALUE2 0, VALUE3 0, VALUE4 0, VALUE5 0")
cmd_no_checks("INST SLRPNLDEPLOY")
cmd_no_checks("INST SLRPNLRESET")
cmd_no_checks("INST ASCIICMD with STRING 'ARM LASER'")
cmd_no_checks("INST COLLECT with DURATION 11, TYPE 'NORMAL'")

cmd_no_checks("INST", "ABORT")
cmd_no_checks("INST", "ARYCMD", "ARRAY" => [])
cmd_no_checks("INST", "CLEAR")
cmd_no_checks("INST", "COLLECT", "DURATION" => 1.0, "TEMP" => 0.0, "TYPE" => 'NORMAL')
cmd_no_checks("INST", "FLTCMD", "FLOAT32" => 0.0, "FLOAT64" => 0.0)
cmd_no_checks("INST", "SETPARAMS", "VALUE1" => 0, "VALUE2" => 0, "VALUE3" => 0, "VALUE4" => 0, "VALUE5" => 0)
cmd_no_checks("INST", "SLRPNLDEPLOY")
cmd_no_checks("INST", "SLRPNLRESET")
cmd_no_checks("INST", "ASCIICMD", "STRING" => 'ARM LASER')
cmd_no_checks("INST", "COLLECT", "DURATION" => 11, "TYPE" => 'NORMAL')

# cmd_no_checks should fail
cmd_no_checks()
cmd_no_checks("BOB")
cmd_no_checks("BOB", "ABORT")
cmd_no_checks("INST", "BOB")
cmd_no_checks("INST", "ABORT", "BOB" => "BOB")
cmd_no_checks("INST", "ABORT", "TED", "BOB" => "BOB")
cmd_no_checks("BOB")
cmd_no_checks("BOB ABORT")
cmd_no_checks("INST BOB")

# send_raw should fail (on demo cmd/tlm server)
send_raw()
send_raw("INT1")
send_raw("INT1", "\x00\x00")
send_raw("INT1", "\x00\x00", "\x00\x00")

# get_all_cmds
expected_cmds = %w(ABORT ARYCMD ASCIICMD CLEAR COLLECT FLTCMD SETPARAMS SLRPNLDEPLOY SLRPNLRESET)
commands = get_all_cmds("INST")
puts commands.inspect

# get_all_cmds should fail
get_all_cmds()
get_all_cmds("BOB")
get_all_cmds("BOB", "TED")

# get_cmd_hazardous
hazardous = get_cmd_hazardous("INST", "COLLECT", "TYPE" => "SPECIAL")
puts hazardous
hazardous = get_cmd_hazardous("INST", "COLLECT", "TYPE" => "NORMAL")
puts hazardous
hazardous = get_cmd_hazardous("INST", "ABORT")
puts hazardous
hazardous = get_cmd_hazardous("INST", "CLEAR")
puts hazardous

# get_cmd_hazardous should fail
get_cmd_hazardous()
get_cmd_hazardous("INST")
get_cmd_hazardous("INST", "COLLECT", "BOB" => 5)
get_cmd_hazardous("INST", "COLLECT", 5)

# tlm
tlm("INST HEALTH_STATUS ARY")
tlm("INST HEALTH_STATUS ASCIICMD")
tlm("INST HEALTH_STATUS CCSDSAPID")
tlm("INST HEALTH_STATUS TEMP1")
tlm("INST HEALTH_STATUS TEMP1", type: :RAW)
tlm("INST HEALTH_STATUS TEMP1", type: :CONVERTED)
tlm("INST HEALTH_STATUS TEMP1", type: :FORMATTED)

tlm("INST", "HEALTH_STATUS", "ARY")
tlm("INST", "HEALTH_STATUS", "ASCIICMD")
tlm("INST", "HEALTH_STATUS", "CCSDSAPID")
tlm("INST", "HEALTH_STATUS", "TEMP1")
tlm("INST", "HEALTH_STATUS", "TEMP1", type: :RAW)
tlm("INST", "HEALTH_STATUS", "TEMP1", type: :CONVERTED)
tlm("INST", "HEALTH_STATUS", "TEMP1", type: :FORMATTED)

# tlm should fail
tlm()
tlm("BOB")
tlm("INST")
tlm("INST BOB")
tlm("INST HEALTH_STATUS")
tlm("INST HEALTH_STATUS BOB")
tlm("INST HEALTH_STATUS ARY BOB")
tlm("INST", "BOB")
tlm("INST", "HEALTH_STATUS")
tlm("INST", "HEALTH_STATUS", "BOB")
tlm("INST", "HEALTH_STATUS", "ARY", "BOB")

# override_tlm
override_tlm("INST HEALTH_STATUS ARY = [0,0,0,0,0,0,0,0,0,0]")
override_tlm("INST HEALTH_STATUS ASCIICMD = 'HI'")
override_tlm("INST HEALTH_STATUS CCSDSAPID = 1000")
override_tlm("INST HEALTH_STATUS TEMP1 = 15")
data = Array.new(131072 / 8) { rand(0..255) }.pack("C*")
override_tlm("INST", "IMAGE", "IMAGE", data)

wait_check("INST HEALTH_STATUS ARY == [1,2,3]", 5)
wait_check("INST HEALTH_STATUS ASCIICMD == 'HI'", 5)
wait_check("INST HEALTH_STATUS CCSDSAPID == 1000", 5)
wait_check("INST HEALTH_STATUS TEMP1 == 15", 5)

# normalize_tlm
normalize_tlm("INST HEALTH_STATUS ARY")
normalize_tlm("INST HEALTH_STATUS ASCIICMD")
normalize_tlm("INST HEALTH_STATUS CCSDSAPID")
normalize_tlm("INST HEALTH_STATUS TEMP1")
normalize_tlm("INST IMAGE IMAGE")

wait_check("INST HEALTH_STATUS ARY != [1,2,3]", 5)
wait_check("INST HEALTH_STATUS ASCIICMD != 'HI'", 5)
wait_check("INST HEALTH_STATUS CCSDSAPID != 1000", 5)
wait_check("INST HEALTH_STATUS TEMP1 != 15", 5)
