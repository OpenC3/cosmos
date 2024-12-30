scripts = script_list()
length = scripts.length
check_expression("#{length} > 100")

contents = "puts('bad"
result = script_create("INST/procedures/new_script.rb", contents)
puts result
check_expression("#{script_list().length} == #{length + 1}")

result = script_syntax_check("INST/procedures/new_script.rb")
puts result
check_expression("#{result['success']} == false")

contents = 'puts "Hello from Ruby"'
result = script_create("INST/procedures/new_script.rb", contents)
puts result
check_expression("#{script_list().length} == #{length + 1}")

result = script_syntax_check("INST/procedures/new_script.rb")
puts result
check_expression("#{result['success']} == true")

script = script_body("INST/procedures/new_script.rb")
check_expression("'#{script}' == 'puts \"Hello from Ruby\"'")

id = script_run("INST/procedures/new_script.rb")
puts id
check_expression("#{id.to_i} > 0")

script = script_instrumented("INST/procedures/new_script.rb")
puts script
check_expression("#{script.include?('RunningScript')} == true")

script_lock("INST/procedures/new_script.rb")
script_unlock("INST/procedures/new_script.rb")
script_delete("INST/procedures/new_script.rb")
