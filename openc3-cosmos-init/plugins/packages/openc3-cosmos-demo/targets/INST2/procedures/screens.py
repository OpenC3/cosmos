all_screens = get_screen_list()
print(all_screens["INST2"])
wait(1)
definition = get_screen_definition("INST2", "ADCS")
print(definition)
wait(1)
display_screen("INST2", "ADCS")
wait(2)
display_screen("INST2", "HS", 400, 0)
wait(2)
clear_screen("INST2", "ADCS")
wait(2)
display_screen("INST2", "IMAGE")
wait(2)
clear_all_screens()
wait(2)
definition = """
SCREEN AUTO AUTO 1.0

VERTICALBOX "Test Screen"
  LABELVALUE INST2 HEALTH_STATUS TEMP1
  LABELVALUE INST2 HEALTH_STATUS RECEIVED_TIMEFORMATTED FORMATTED 30
END
"""
local_screen("TEST", definition)
wait(2)
clear_all_screens()
create_screen("INST2", "TEST", definition)
display_screen("INST2", "TEST")
wait(2)
clear_all_screens()
delete_screen("INST2", "TEST")
display_screen("INST2", "TEST")  # Expected to fail because new screen was deleted
