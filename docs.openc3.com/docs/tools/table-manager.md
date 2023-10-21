---
title: Table Manager
---

## Introduction

Table Manager is a binary file editor. It takes binary file [definitions](../configuration/table.md) similar to the COSMOS command packet definitions and builds a GUI to edit the fields in the binary file.

![Table Manager](/img/v5/table_manager/table_manager.png)

### File Menu Items

<!-- Image sized to match up with bullets -->

<img src="/img/v5/table_manager/file_menu.png"
alt="File Menu"
style={{"float": 'left', "margin-right": 50 + 'px', "height": 200 + 'px'}} />

- Create a new binary based on [definition](../configuration/table.md)
- Open an existing binary
- Save the current binary
- Rename the current binary
- Delete the current binary

## File Download

The three buttons next to File Download download the binary file, the [definition](../configuration/table.md) file, and the report file. The binary is the raw bits defined by the table. The [definition](../configuration/table.md) is the structure definition of those raw bits. The report file is a Table Manager generated CSV that shows all the table values in the binary.

## Upload / Download

Table Manager has the ability to directly call a COSMOS script to upload a binary file to a target or download a file into Table Manager. If a file called `upload.rb` is found in the Target's procedures directory then the Upload button becomes active. If a file called `download.rb` is found in the Target's procedures directory then the Download button becomes active. The B/G button indicates whether to run the upload / download scripts in the background. If you uncheck this box a new Script Runner window will show the line by line execution of the script.

### upload.rb

The COSMOS demo creates the following `upload.rb` script. Note that the `ENV['TBL_FILENAME']` is set to the name of the table file and the script uses `get_target_file` to get access to the file. At this point the logic to upload the file to the target is specific to the commanding defined by the target but an example script is given.

```ruby
# TBL_FILENAME is set to the name of the table file
puts "file:#{ENV['TBL_FILENAME']}"
# Open the file
file = get_target_file(ENV['TBL_FILENAME'])
buffer = file.read
# puts buffer.formatted
# Implement custom commanding logic to upload the table
# Note that buffer is a Ruby string of bytes
# You probably want to do something like:
# buf_size = 512 # Size of a buffer in the upload command
# i = 0
# while i < buffer.length
#   # Send a part of the buffer
#   # NOTE: triple dots means start index, up to but not including, end index
#   #   while double dots means start index, up to AND including, end index
#   cmd("TGT", "UPLOAD", "DATA" => buffer[i...(i + buf_size)])
#   i += buf_size
# end
file.delete
```

### download.rb

The COSMOS demo creates the following `download.rb` script. Note that the `ENV['TBL_FILENAME']` is set to the name of the table file to OVERWRITE and the script uses `put_target_file` to get access to the file. At this point the logic to download the file from the target is specific to the commanding defined by the target but an example script is given.

```ruby
# TBL_FILENAME is set to the name of the table file to overwrite
puts "file:#{ENV['TBL_FILENAME']}"
# Download the file
# Implement custom commanding logic to download the table
# You probably want to do something like:
buffer = ''
# i = 1
# num_segments = 5 # calculate based on TBL_FILENAME
# table_id = 1  # calculate based on TBL_FILENAME
# while i < num_segments
#   # Request a part of the table buffer
#   cmd("TGT DUMP with TABLE_ID #{table_id}, SEGMENT #{i}")
#   buffer += tlm("TGT DUMP_PKT DATA")
#   i += 1
# end
put_target_file(ENV['TBL_FILENAME'], buffer)
```
