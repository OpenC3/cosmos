from openc3.script import *

# Example of using metadata. Note each call to metadata_set creates a new entry.
# metadata_update without a start time will update the latest metadata entry.
print(metadata_get())
print(metadata_set({"setkey": 1}))
check_expression(f"{len(metadata_all())} >= 1")
check_expression(f"{metadata_get()['metadata']} == {{'setkey':1}}")
print(metadata_get()["metadata"])
print(metadata_update({"setkey": 2, "updatekey": 3}))
check_expression(f"{metadata_get()['metadata']['setkey']} == 2")
check_expression(f"{metadata_get()['metadata']['updatekey']} == 3")
print(metadata_update({"setkey": 4}))  # Ensure updatekey stays
check_expression(f"{metadata_get()['metadata']['setkey']} == 4")
check_expression(f"{metadata_get()['metadata']['updatekey']} == 3")
check_expression(f"{len(metadata_all())} >= 1")
# TODO: metadata_input()  # Creates a new entry
metadata_set({"input": 5})  # Simulate metadat_input for now
check_expression(f"{len(metadata_all())} >= 2")
wait(2)  # Allow time to advance or it's an error
metadata_set({"new": 5})  # Another new entry
check_expression(f"{len(metadata_all())} >= 3")
# The first entry is the newest one we created
print(metadata_all)
check_expression(f"{metadata_all()[0]['metadata']} == {{'new':5}}")
