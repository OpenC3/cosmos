import os

# TBL_FILENAME is set to the name of the table file to overwrite
print(f"file:{os.getenv('TBL_FILENAME')}")
# Download the file
# Implement custom commanding logic to download the table
# You probably want to do something like:
buffer = ""
# i = 1
# num_segments = 5 # calculate based on TBL_FILENAME
# table_id = 1  # calculate based on TBL_FILENAME
# while i < num_segments:
#   # Request a part of the table buffer
#   cmd(f"TGT DUMP with TABLE_ID {table_id}, SEGMENT {i}")
#   buffer += tlm("TGT DUMP_PKT DATA")
#   i += 1
put_target_file(os.getenv("TBL_FILENAME"), buffer)
