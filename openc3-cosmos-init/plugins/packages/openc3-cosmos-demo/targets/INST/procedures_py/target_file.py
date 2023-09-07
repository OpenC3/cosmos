from openc3.script import *
from openc3.utilities.string import formatted
import tempfile

put_target_file("INST/test.txt", "this is a string test")
download_file("INST/test.txt")  # download via path
file = get_target_file("INST/test.txt")
print(file.read())
file.seek(0)  # rewind so download_file can read
download_file(file)  # download using file
file.close()  # closing deletes tempfile
delete_target_file("INST/test.txt")

save_file = tempfile.NamedTemporaryFile(mode="w+t")
save_file.write("this is a Io test")
save_file.seek(0)
put_target_file("INST/test.txt", save_file)
save_file.close()  # Delete the tempfile
file = get_target_file("INST/test.txt")
print(file.read())
file.close()
delete_target_file("INST/test.txt")

# TODO: Binary not yet supported
# put_target_file("INST/test.bin", b"\x00\x01\x02\x03\xFF\xEE\xDD\xCC")
# file = get_target_file("INST/test.bin")
# print(formatted(file.read()))
# file.close()
# delete_target_file("INST/test.bin")
