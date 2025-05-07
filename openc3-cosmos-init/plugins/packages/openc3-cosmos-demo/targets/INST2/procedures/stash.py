# Stash API is useful for storing simple key/value pairs
# to preserve state between script runs
stash_set("key1_py", "val1")
stash_set("key2_py", "val2")
check_expression(f"'{stash_get('key1_py')}' == 'val1'")
check_expression(f"'{stash_get('key2_py')}' == 'val2'")
stash_set("key1_py", 1)
stash_set("key2_py", 2)
check_expression(f"'{stash_get('key1_py')}' == '1'")
check_expression(f"'{stash_get('key2_py')}' == '2'")
stash_delete("key2_py")
check_expression(f"{stash_get('key2_py')} == None")
stash_delete("key1_py")
data = [1, 2, [3, 4]]
stash_set("ary_py", data)
check_expression(f"{stash_get('ary_py')} == {data}")
stash_delete("ary_py")
data = {"one": 1, "two": 2, "string": "string"}
stash_set("data_py", data)
check_expression(f"{stash_get('data_py')} == {data}")
stash_delete("data_py")
