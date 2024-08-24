# Example of using metadata. Note each call to metadata_set creates a new entry.
# metadata_update without a start time will update the latest metadata entry.
puts metadata_get()
puts metadata_set({ 'setkey' => 1 })
check_expression("#{metadata_all().length} >= 1")
check_expression("#{metadata_get()['metadata']} == {\"setkey\"=>1}")
puts metadata_get()['metadata']
puts metadata_update({ 'setkey' => 2, 'updatekey' => 3 })
check_expression("#{metadata_get()['metadata']['setkey']} == 2")
check_expression("#{metadata_get()['metadata']['updatekey']} == 3")
puts metadata_update({ 'setkey' => 4 }) # Ensure updatekey stays
check_expression("#{metadata_get()['metadata']['setkey']} == 4")
check_expression("#{metadata_get()['metadata']['updatekey']} == 3")
check_expression("#{metadata_all().length} >= 1")
metadata_input() # Creates a new entry
check_expression("#{metadata_all().length} >= 2")
wait 2 # Allow time to advance or it's an error
metadata_set({ 'new' => 5 }) # Another new entry
check_expression("#{metadata_all().length} >= 3")
puts metadata_all()
