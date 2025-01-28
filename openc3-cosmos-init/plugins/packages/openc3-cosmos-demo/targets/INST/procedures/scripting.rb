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

SCRIPT_NAME = "INST/procedures/new_script.rb"

# Ensure it's not already there
step_mode()
script_delete(SCRIPT_NAME)
scripts = script_list()
check_expression("#{scripts.length} > 100")
run_mode()

contents = "puts('bad"
script_create(SCRIPT_NAME, contents)
body = script_body(SCRIPT_NAME)
result = script_syntax_check(body)
check_expression("#{result['success']} == false")

# Create a valid script that doesn't complete
contents = "set_line_delay(1)\nputs 'Hello from Ruby'\nputs('.')\nputs('.')\nwhile true\nputs Time.now\nwait 0.5\nwait 0.5\nend"
script_create(SCRIPT_NAME, contents)
scripts = script_list()
check_expression("#{scripts.include?(SCRIPT_NAME)} == true")

script = script_instrumented(contents)
check_expression("#{script.include?('RunningScript')} == true")

id = script_run(SCRIPT_NAME)
check_expression("#{id.to_i} > 0")
wait_for_action(id, 'running')

list = running_script_list()
started = list.select {|script| script["id"] == id}[0]
check_expression("'#{started['name']}' == SCRIPT_NAME")
script = running_script_get(id)
check_expression("'#{script['name']}' == SCRIPT_NAME")

running_script_pause(id)
wait_for_action(id, 'paused')
running_script_step(id)
wait_for_action(id, 'paused')
running_script_retry(id)
wait_for_action(id, 'paused')
running_script_go(id)
wait_for_action(id, 'running')
running_script_stop(id)
wait 1

list = running_script_list()
script = list.select {|script| script["id"] == id}[0]
# Script is stopped so it should NOT be in the running list
check_expression("#{script.nil?} == true")

list = completed_script_list()
script = list.select {|script| script["id"] == id}[0]
# Script is completed so it should be in the completed list
check_expression("#{script.nil?} == false")

id = script_run(SCRIPT_NAME)
wait_for_action(id, 'running')
running_script_delete(id) # Stop and completely remove the script
wait 1

list = running_script_list()
script = list.select {|script| script["id"] == id}[0]
# Script is deleted, so it should NOT be in the running list
check_expression("#{script.nil?} == true")
list = completed_script_list()
# Script is deleted so it should be in the completed list
script = list.select {|script| script["id"] == id}[0]
check_expression("#{script.nil?} == false")

script_lock(SCRIPT_NAME)
script_unlock(SCRIPT_NAME)
script_delete(SCRIPT_NAME)
scripts = script_list()
check_expression("#{scripts.include?(SCRIPT_NAME)} == false")
