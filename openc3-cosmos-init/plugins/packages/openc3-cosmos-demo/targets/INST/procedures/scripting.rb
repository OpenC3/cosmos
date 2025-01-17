# Helper method to check for a script to change state
def wait_for_action(id, state)
  i = 0
  while i < 100
    script = running_script_get(id)
    if script['state'] == state
      check_expression("'#{script['state']}' == '#{state}'")
      break
    end
    wait 0.1
  end
  check_expression("'#{script['state']}' == '#{state}'")
end

# Ensure it's not already there
step_mode()
script_delete("INST/procedures/new_script.rb")
scripts = script_list()
check_expression("#{scripts.length} > 100")
run_mode()

contents = "puts('bad"
script_create("INST/procedures/new_script.rb", contents)
body = script_body("INST/procedures/new_script.rb")
result = script_syntax_check(body)
check_expression("#{result['success']} == false")

# Create a valid script that doesn't complete
contents = "set_line_delay(1)\nputs 'Hello from Ruby'\nputs('.')\nputs('.')\nwhile true\nputs Time.now\nwait 0.5\nwait 0.5\nend"
script_create("INST/procedures/new_script.rb", contents)
scripts = script_list()
check_expression("#{scripts.include?('INST/procedures/new_script.rb')} == true")

script = script_instrumented(contents)
check_expression("#{script.include?('RunningScript')} == true")

id = script_run("INST/procedures/new_script.rb")
check_expression("#{id.to_i} > 0")
wait_for_action(id, 'running')

list = running_script_list()
started = list.select {|script| script["id"] == id}[0]
check_expression("'#{started['name']}' == 'INST/procedures/new_script.rb'")
script = running_script_get(id)
check_expression("'#{script['name']}' == 'INST/procedures/new_script.rb'")

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
script = list.select {|script| script["id"] == id}[0]
# Script is stopped so it should NOT be in the running list
check_expression("#{script.nil?} == true")

list = completed_script_list()
script = list.select {|script| script["id"] == id}[0]
# Script is completed so it should be in the completed list
check_expression("#{script.nil?} == false")

id = script_run("INST/procedures/new_script.rb")
wait_for_action(id, 'running')
running_script_delete(id)
# Can't wait for stopped action because we delete the script so just wait
wait 1

list = running_script_list()
script = list.select {|script| script["id"] == id}[0]
# Script is stopped, so it should NOT be in the running list
check_expression("#{script.nil?} == true")
list = completed_script_list()
# Script is completed so it should be in the completed list
script = list.select {|script| script["id"] == id}[0]
check_expression("#{script.nil?} == false")

script_lock("INST/procedures/new_script.rb")
script_unlock("INST/procedures/new_script.rb")
script_delete("INST/procedures/new_script.rb")
scripts = script_list()
check_expression("#{scripts.include?('INST/procedures/new_script.rb')} == false")
