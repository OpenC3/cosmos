# Stash API is useful for storing simple key/value pairs
# to preserve state between script runs
stash_set('key1', 'val1')
stash_set('key2', 'val2')
check_expression("'#{stash_get('key1')}' == 'val1'")
check_expression("'#{stash_get('key2')}' == 'val2'")
check_expression("'#{stash_keys().to_s}' == '[\"key1\", \"key2\"]'")
stash_set('key1', 1)
stash_set('key2', 2)
check_expression("'#{stash_all().to_s}' == '{\"key1\"=>1, \"key2\"=>2}'")
stash_delete('key2')
check_expression("#{stash_get('key2').nil?} == true")
