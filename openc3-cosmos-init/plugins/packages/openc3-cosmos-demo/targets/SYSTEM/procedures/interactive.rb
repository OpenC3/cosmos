# This script checks all the interactive APIs
prompt("Would you like to continue?")
answer = combo_box("This is a plain combo box", 'one', 'two', 'three', informative: nil)
puts "answer:#{answer}"
answer = combo_box("This is a combo box with info", 'one', 'two', 'three', informative: 'This is informative')
puts "answer:#{answer}"
answer = combo_box("This is a combo box with details", 'one', 'two', 'three', informative: nil, details: 'This is some details')
puts "answer:#{answer}"
answer = combo_box("This is a combo box with info & details", 'one', 'two', 'three', informative: 'This is informative', details: 'Details details details!')
puts "answer:#{answer}"
answer = combo_box("This is a combo box", 'one', 'two', 'three', details: "Some more stuff")
puts "answer:#{answer}"
answer = combo_box("This is a multi-select combo box", 'one', 'two', 'three', multiple: true)
puts "answer:#{answer} len:#{answer.length} [0]:#{answer[0]}"
answer = check_box("This is a check box", 'one', 'two', 'three')
puts "answer:#{answer} len:#{answer.length} [0]:#{answer[0]}"
answer = check_box("This is a check box with info & details", 'one', 'two', 'three', informative: 'This is informative', details: 'Details details details!')
puts "answer:#{answer} len:#{answer.length} [0]:#{answer[0]}"
answer = prompt("This is a test", details: "Some more stuff")
puts "answer:#{answer}"
answer = prompt("This is a test", details: "Some more stuff")
puts "answer:#{answer}"
answer = message_box('This is a message box', 'one', 'two', 'three', informative: "Informative stuff", details: "Some more stuff")
puts "answer:#{answer}"
answer = vertical_message_box('This is a message box', 'one', 'two', 'three', informative: "Informative stuff", details: "Some more stuff")
puts "answer:#{answer}"
answer = ask("Let me ask you a question", "default")
puts "answer:#{answer} class:#{answer.class}"
raise "Not a string" unless answer.is_a? String
answer = ask("Let me ask you a question", 10)
puts "answer:#{answer} class:#{answer.class}"
raise "Not an integer" unless answer.is_a? Integer
answer = ask("Let me ask you a question", 10.5)
puts "answer:#{answer} class:#{answer.class}"
raise "Not a float" unless answer.is_a? Float
answer = ask_string("Let me ask you a question", "default")
puts "answer:#{answer} class:#{answer.class}"
answer = ask_string("Let me ask you a question", 10)
puts "answer:#{answer} class:#{answer.class}"
raise "Not a string" unless answer.is_a? String
answer = ask("Enter a blank (return)", true) # allow blank
puts "answer:#{answer}"
answer = ask("Password", false, true) # password required
puts "answer:#{answer}"
