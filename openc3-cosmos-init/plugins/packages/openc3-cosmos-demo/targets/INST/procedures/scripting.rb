scripts = script_list()
length = scripts.length
check_expression("#{length} > 100")

contents = "puts('bad"
result = script_create("INST/procedures/new_script.rb", contents)
puts result
check_expression("#{script_list().length} == #{length + 1}")

script = script_body("INST/procedures/new_script.rb")
result = script_syntax_check(script)
puts result
check_expression("#{result['success']} == false")

contents = 'puts "Hello from Ruby"'
result = script_create("INST/procedures/new_script.rb", contents)
puts result
check_expression("#{script_list().length} == #{length + 1}")

script = script_body("INST/procedures/new_script.rb")
check_expression("'#{script}' == 'puts \"Hello from Ruby\"'")
result = script_syntax_check(script)
puts result
check_expression("#{result['success']} == true")

id = script_run("INST/procedures/new_script.rb")
puts id
check_expression("#{id.to_i} > 0")

script = script_instrumented(script)
puts script
check_expression("#{script.include?('RunningScript')} == true")

script_lock("INST/procedures/new_script.rb")
script_unlock("INST/procedures/new_script.rb")
script_delete("INST/procedures/new_script.rb")
