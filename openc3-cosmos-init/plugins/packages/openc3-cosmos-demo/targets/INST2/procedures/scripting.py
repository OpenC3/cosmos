scripts = script_list()
length = len(scripts)
check_expression(f"{length} > 100")

contents = "print('bad"
result = script_create("INST2/procedures/new_script.py", contents)
print(result)
check_expression(f"{len(script_list())} == {length + 1}")

script = script_body("INST2/procedures/new_script.py")
result = script_syntax_check(script)
print(result)
check_expression(f"{result['success']} == False")

contents = 'print("Hello from Python")'
result = script_create("INST2/procedures/new_script.py", contents)
print(result)
check_expression(f"{len(script_list())} == {length + 1}")

script = script_body("INST2/procedures/new_script.py")
check_expression(f"'{script}' == 'print(\"Hello from Python\")'")
result = script_syntax_check("INST2/procedures/new_script.py")
print(result)
check_expression(f"{result['success']} == True")

id = script_run("INST2/procedures/new_script.py")
print(id)
check_expression(f"{int(id)} > 0")

script = script_instrumented(script)
print(script)
check_expression(f"{'RunningScript.instance' in script} == True")

script_lock("INST2/procedures/new_script.py")
script_unlock("INST2/procedures/new_script.py")
script_delete("INST2/procedures/new_script.py")
