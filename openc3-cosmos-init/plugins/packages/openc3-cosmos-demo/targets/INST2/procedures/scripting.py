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

# Ensure it's not already there
script_delete("INST2/procedures/new_script.py")
scripts = script_list()
check_expression(f"{len(scripts)} > 100")

contents = "print('bad"
script_create("INST2/procedures/new_script.py", contents)
body = script_body("INST2/procedures/new_script.py")
result = script_syntax_check(body)
check_expression(f"{result['success']} == False")

contents = 'set_line_delay(1)\nprint("Hello from Python")\nprint(".")\nprint(".")\nwhile True:\n  print(".")\n  wait(0.5)\n  wait(0.5)\n'
result = script_create("INST2/procedures/new_script.py", contents)
scripts = script_list()
check_expression(f"{'INST2/procedures/new_script.py' in scripts} == True")

script = script_instrumented(contents)
check_expression(f"{'RunningScript.instance' in script} == True")

id = script_run("INST2/procedures/new_script.py")
check_expression(f"{int(id)} > 0")
wait_for_action(id, 'running')

list = running_script_list()
started = [script for script in list if script["id"] == id][0]
check_expression(f"'{started['name']}' == 'INST2/procedures/new_script.py'")
script = running_script_get(id)
check_expression(f"'{script['name']}' == 'INST2/procedures/new_script.py'")

running_script_pause(id)
wait_for_action(id, 'paused')
running_script_step(id)
wait_for_action(id, 'paused')
running_script_retry(id)
wait_for_action(id, 'paused')
running_script_go(id)
wait_for_action(id, 'running')
running_script_stop(id)
wait_for_action(id, 'stopped')

list = running_script_list()
script = [script for script in list if script["id"] == id]
# Script is stopped so it should NOT be in the running list
check_expression(f"{len(script)} == 0")

list = completed_script_list()
script = [script for script in list if script["id"] == id]
# Script is completed so it should be in the completed list
check_expression(f"{len(script)} == 1")

id = script_run("INST2/procedures/new_script.py")
wait_for_action(id, 'running')
running_script_delete(id)
# Can't wait for stopped action because we delete the script so just wait
wait(1)

list = running_script_list()
script = [script for script in list if script["id"] == id]
# Script is stopped, so it should NOT be in the running list
check_expression(f"{len(script)} == 0")
list = completed_script_list()
# Script is completed so it should be in the completed list
script = [script for script in list if script["id"] == id]
check_expression(f"{len(script)} == 1")

script_lock("INST2/procedures/new_script.py")
script_unlock("INST2/procedures/new_script.py")
script_delete("INST2/procedures/new_script.py")
scripts = script_list()
check_expression(f"{'INST2/procedures/new_script.py' not in scripts} == True")
