# Setting up Valkey users

**IMPORTANT:** When setting up OpenC3, please see the section at the bottom for changing the default passwords.

## The ACL file

Valkey reads in the user configuration from an ACL file: [users.acl](./users.acl). Each line has the syntax `user <username> [on/off] <password> [keyspace] [commands]`

Passwords can be set in the ACL file as either the SHA-256 hash or plaintext. To use the hash, prefix it with a # symbol (example: `user bob on #3ff698674f294ba598e719e3bfef82d88836d363b9e6f74d4b684415542919da`). To use plaintext, prefix it with a > symbol (example: `user bob on >bobspassword`). Note that this file gets physically stored on the Valkey server, so storing the passwords in plaintext is not recommended.

### The users:

- openc3
  - Default password: openc3password

  - This user is required, and it's used by OpenC3 to connect to Valkey. It has access to the entire keyspace, but its commands are restricted to what's necessary for OpenC3. As such, someone with this user has access to / ownership of all of the data stored in OpenC3; however, this user cannot reconfigure Valkey itself.

- scriptrunner
  - Default password: scriptrunnerpassword

  - This user is required to use Script Runner. Script Runner needs Valkey to keep track of the scripts it's running, but it has a user with limited access to prevent scripts from being able to destroy or access data they shouldn't be able to.

- admin
  - Disabled (`off`) by default. Its shipped password hash is for `adminpassword`, so set a new password before enabling it.

  - This user is optional, but it's provided so that you can make changes to Valkey while it's running. This won't be needed for normal operation of OpenC3. To enable it, change "off" to "on" and replace the hash with the hash of your own password, then restart Valkey. Leave it disabled unless you need it.

  - It should be noted that the only commands this user has access to are those in the `@admin` category. However, that category includes the `ACL` command and all its subcommands, meaning that the user could grant themselves any other permission in Valkey.

- default
  - This is the default user for Valkey, which has permission to do anything and no password. This user is set to `off` to ensure that it can't be used.

  - You can enable this user if you want a simple way to expose certain commands without needing authentication. For example `user default on nopass -@all +ping` would let anyone ping Valkey, but nothing else.

## The .env file

[This file](../.env) contains the plaintext credentials used by OpenC3 to access Valkey, which are loaded in as environment variables.

## CHANGING THE PASSWORDS WHEN SETTING UP OPENC3

A utility script has been provided to calculate the SHA-256 hash of a string.

        OPENC3> openc3.bat util hash yourpasswordhere

1.  Pick a new password for the 'openc3' user.
    - Set that value in plaintext to the `OPENC3_REDIS_PASSWORD` variable in .env.local (see the security docs; do not edit .env)
    - Set it as either plaintext or its SHA-256 hash in the ACL file, as described above (with > or #)

1.  Pick a new password for the 'scriptrunner' user.
    - Set that value in plaintext to the `OPENC3_SR_REDIS_PASSWORD` variable in .env.local (see the security docs; do not edit .env)
    - Set its SHA-256 hash in the ACL file

1.  If you enable the 'admin' user, pick a new password for it first.
    - The only place you need to put its password is in the ACL file.
