# Script Runner test script
cmd("PW_TEST EXAMPLE")
wait_check("PW_TEST STATUS BOOL == 'FALSE'", 5)
