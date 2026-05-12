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

# Specify the title and message
file = open_bucket_dialog(
    "Open a file from the buckets", "Choose something interesting"
)
print(file)  # Python tempfile.NamedTemporaryFile object
print(file.filename())  # Filename that was selected in the dialog
print(file.read())
file.close()

# Pre-select the procedures folder and restrict to .py files.
# default_path uses the form bucket/path - trailing slash means folder.
file = open_bucket_dialog(
    "Pick a procedure",
    "Defaults to INST2 procedures, .py only",
    default_path="config/DEFAULT/targets/INST2/procedures/",
    filter=".py",
)
print(file.filename())
file.close()
