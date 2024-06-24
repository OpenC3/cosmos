#!/bin/bash

# https://stackoverflow.com/a/246128
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Initialize an empty storageState.
# The script that populates this file also attempts to read it, and so needs some initial state.
echo "{}" > ${SCRIPT_DIR}/storageState.json
echo "{}" > ${SCRIPT_DIR}/adminStorageState.json
