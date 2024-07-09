from openc3.utilities.string import formatted
import tempfile

put_target_file("INST2/test.txt", "this is a string test")
download_file("INST2/test.txt")
file = get_target_file("INST2/test.txt")
print(file.read())
file.close()  # closing deletes tempfile
delete_target_file("INST2/test.txt")

save_file = tempfile.NamedTemporaryFile(mode="w+t")
save_file.write("this is a Io test")
save_file.seek(0)
put_target_file("INST2/test.txt", save_file)
save_file.close()  # Delete the tempfile
file = get_target_file("INST2/test.txt")
print(file.read())
file.close()
delete_target_file("INST2/test.txt")

put_target_file("INST2/test.bin", b"\x00\x01\x02\x03\xFF\xEE\xDD\xCC")
download_file("INST2/test.bin")
file = get_target_file("INST2/test.bin")
print(formatted(file.read()))
file.close()
delete_target_file("INST2/test.bin")
