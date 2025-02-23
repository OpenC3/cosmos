# Helper method to check for a script to change state
def wait_for_action(id, state):
    i = 0
    while i < 100:
        script = running_script_get(id)
        if script['state'] == state:
            check_expression(f"'{script['state']}' == '{state}'")
            break
        wait(0.1)
    check_expression(f"'{script['state']}' == '{state}'")

SCRIPT_NAME = "INST2/procedures/new_script.py"

# Ensure it's not already there
step_mode()
script_delete(SCRIPT_NAME)
scripts = script_list()
check_expression(f"{len(scripts)} > 100")
run_mode()

contents = "print('bad"
script_create(SCRIPT_NAME, contents)
body = script_body(SCRIPT_NAME)
result = script_syntax_check(body)
check_expression(f"{result['success']} == False")

contents = 'set_line_delay(1)\nprint("Hello from Python")\nprint(".")\nprint(".")\nwhile True:\n  print(".")\n  wait(0.5)\n  wait(0.5)\n'
result = script_create(SCRIPT_NAME, contents)
scripts = script_list()
check_expression(f"{SCRIPT_NAME in scripts} == True")

script = script_instrumented(contents)
check_expression(f"{'RunningScript.instance' in script} == True")

id = script_run(SCRIPT_NAME)
check_expression(f"{int(id)} > 0")
wait_for_action(id, 'running')

list = running_script_list()
started = [script for script in list if script["id"] == id][0]
check_expression(f"'{started['name']}' == '{SCRIPT_NAME}'")
script = running_script_get(id)
check_expression(f"'{script['name']}' == '{SCRIPT_NAME}'")

running_script_pause(id)
wait_for_action(id, 'paused')
running_script_step(id)
wait_for_action(id, 'paused')
running_script_retry(id)
wait_for_action(id, 'paused')
running_script_go(id)
wait_for_action(id, 'running')
running_script_stop(id)
wait(1)

list = running_script_list()
script = [script for script in list if script["id"] == id]
# Script is stopped so it should NOT be in the running list
check_expression(f"{len(script)} == 0")

list = completed_script_list()
script = [script for script in list if script["id"] == id]
# Script is completed so it should be in the completed list
check_expression(f"{len(script)} == 1")

id = script_run(SCRIPT_NAME)
wait_for_action(id, 'running')
running_script_delete(id) # Stop and completely remove the script
wait(1)

list = running_script_list()
script = [script for script in list if script["id"] == id]
# Script is deleted, so it should NOT be in the running list
check_expression(f"{len(script)} == 0")
list = completed_script_list()
# Script is deleted so it should be in the completed list
script = [script for script in list if script["id"] == id]
check_expression(f"{len(script)} == 1")

script_lock(SCRIPT_NAME)
script_unlock(SCRIPT_NAME)
script_delete(SCRIPT_NAME)
scripts = script_list()
check_expression(f"{SCRIPT_NAME not in scripts} == True")
