# Specify the title and message and filter to txt files
file = open_file_dialog("Open a single file", "Choose something interesting", filter: ".txt")
puts file # Ruby File object
puts file.path # Path of the tempfile (generally not used)
puts file.filename # Filename that was selected in the dialog
puts file.read
file.delete

files = open_files_dialog("Open multiple files") # message is optional
puts files # Array of File objects (even if you select only one)
files.each do |file|
  puts file.filename
  puts file.read
  file.delete
end
