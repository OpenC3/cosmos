# API Architecture

All the files under lib/openc3/api define methods which are added to the WHITELIST. Then in lib/openc3/script/script.rb they are defined as methods on the $api_server which proxies the methods as requests to the JsonDRbObject.

They use Models to store data back to the Redis data store after using authorize() to ensure permission.
