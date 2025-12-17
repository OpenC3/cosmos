queue_create("QUEUEAPI")
cmd("INST MEMLOAD with DATA 0xDEAD", queue: "QUEUEAPI")
cmd("INST MEMLOAD with DATA 0xBEEF", queue: "QUEUEAPI")
cmd("INST ABORT", queue: "QUEUEAPI")
cmd("INST ARYCMD with ARRAY [1,2,3], CRC 0", queue: "QUEUEAPI")
cmd("INST ASCIICMD with STRING 'NOOP', BINARY 0xDEADBEEF, ASCII '0xDEADBEEF'", queue: "QUEUEAPI")
cmd("INST CLEAR", queue: "QUEUEAPI")
cmd("INST COLLECT with TYPE NORMAL, DURATION 1.0, OPCODE 171, TEMP 0.0", queue: "QUEUEAPI")
cmd("INST FLTCMD with FLOAT32 0.0, FLOAT64 0.0", queue: "QUEUEAPI")
cmd("INST MEMLOAD with DATA 0xABCD", queue: "QUEUEAPI")
cmd("INST SETPARAMS with VALUE1 1, VALUE2 1, VALUE3 1, VALUE4 1, VALUE5 1, BIGINT 0", queue: "QUEUEAPI")
cmd("INST SLRPNLDEPLOY", queue: "QUEUEAPI")
cmd("INST SLRPNLRESET", queue: "QUEUEAPI")
cmd("INST TIME_OFFSET with SECONDS 0, IP_ADDRESS 127.0.0.1", queue: "QUEUEAPI")

queue_remove("QUEUEAPI", 2) # Should remove INST MEMLOAD with DATA 0xBEEF
queue_exec("QUEUEAPI") # Should execute INST MEMLOAD with DATA 0xDEAD
wait

queue_disable("QUEUEAPI")
cmd("INST ABORT", queue: "QUEUEAPI") # This will raise an error since the queue is disabled
queue_hold("QUEUEAPI")
wait
queue_release("QUEUEAPI")
