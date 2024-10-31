---
title: Command History (Enterprise)
---

## Introduction

Command History provides the ability to see all the commands sent in COSMOS. Commands are listed in time execution order and include who sent the command and whether they were successful (if validated).

![Command History](/img/command_history/command_history.png)

### Selecting Time

By default, Command History displays the last hour of commands and then continues streaming commands as they are sent. You can select a different time range using the start date / time and end date / time choosers.

## Commands Table

The commands table is sorted by Time and list the User (or process), the Command, the Result and an optional Description.

As shown above, the User can be an actual user in the system (admin, operator) or a background process (DEFAULT\_\_MULTI\_\_INST, DEFAULT\_\_DECOM\_\_INST2).

The Result field is the result of executing Command Validators established by the [VALIDATOR](../configuration/command#validator) keyword. Command Validators are either a Ruby or Python class which is used to validate the command success or failure with both a pre_check and post_check method. Usually when a command fails, a description is given as in the example above.

For more information read the [VALIDATOR](../configuration/command#validator) documentation and also see the [Ruby Example](https://github.com/OpenC3/cosmos/blob/main/openc3-cosmos-init/plugins/packages/openc3-cosmos-demo/targets/INST/lib/inst_cmd_validator.rb) and the [Python Example](https://github.com/OpenC3/cosmos/blob/main/openc3-cosmos-init/plugins/packages/openc3-cosmos-demo/targets/INST2/lib/inst2_cmd_validator.py) in the [COSMOS Demo](https://github.com/OpenC3/cosmos/tree/main/openc3-cosmos-init/plugins/packages/openc3-cosmos-demo).
