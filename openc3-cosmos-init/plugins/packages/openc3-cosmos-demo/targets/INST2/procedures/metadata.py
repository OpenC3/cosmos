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
metadata_input()  # Creates a new entry
check_expression(f"{len(metadata_all())} >= 2")
# Only one entry can exist per second. metadata_input() creates its entry from
# the dialog, which defaults the start to the next 30 minute boundary, so a
# metadata_set() at the current time can land on that same second. Pass an
# explicit start derived from the newest entry (metadata_all is sorted newest
# first) so the two can never collide no matter when the script runs.
metadata_set({"new": 5}, start=metadata_all()[0]["start"] + 1)  # Another new entry
check_expression(f"{len(metadata_all())} >= 3")
print(metadata_all())
