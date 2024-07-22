# Specify the title and message and filter to txt files
file = open_file_dialog(
    "Open a single file", "Choose something interesting", filter=".txt"
)
print(file)  # Python tempfile.NamedTemporaryFile object
print(file.filename())  # Filename that was selected in the dialog
print(file.read())
file.close()

files = open_files_dialog("Open multiple files")  # message is optional
print(
    files
)  # Array of tempfile.NamedTemporaryFile objects (even if you select only one)
for file in files:
    print(file.filename())
    print(file.read())
    file.close()
