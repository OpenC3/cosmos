all_screens = get_screen_list()
puts all_screens["INST"]
wait(1)
definition = get_screen_definition("INST", "ADCS")
puts definition
wait(1)
display_screen("INST", "ADCS")
wait(2)
display_screen("INST", "HS", 400, 0)
wait(2)
clear_screen("INST", "ADCS")
wait(2)
display_screen("INST", "IMAGE")
wait(2)
clear_all_screens()
wait(2)
definition = '
SCREEN AUTO AUTO 1.0

VERTICALBOX "Test Screen"
  LABELVALUE INST HEALTH_STATUS TEMP1
  LABELVALUE INST HEALTH_STATUS RECEIVED_TIMEFORMATTED FORMATTED 30
END
'
local_screen("TEST", definition)
wait(2)
clear_all_screens()
create_screen("INST", "TEST", definition)
display_screen("INST", "TEST")
wait(2)
clear_all_screens()
delete_screen("INST", "TEST")
display_screen("INST", "TEST") # Expected to fail because new screen was deleted
