---
title: Exposing Microservices
description: Provide external accessibility to microservices
sidebar_custom_props:
  myEmoji: 🚪
---

COSMOS provides a simple method to add new APIs and make custom microservices and interfaces accessible to the network.

:::warning Make sure anything you expose is secure

Make sure that any new apis you expose check for user credentials and authorize actions appropriately.
:::

## Expose microservices using the PORT and ROUTE_PREFIX keywords

In your plugin.txt file, both [INTERFACE](../configuration/plugins#interface-1) and [MICROSERVICE](../configuration/plugins#microservice-1) support the keywords [PORT](../configuration/plugins#port-1) and [ROUTE_PREFIX](../configuration/plugins#route_prefix-1).

[PORT](../configuration/plugins#port-1) is used to declare the port(s) that your microservice is listening for connections on. This is used in combination with [ROUTE_PREFIX](../configuration/plugins#route_prefix-1) to create a dynamic traefik route to your microservice.

The following code is used internally to let traefik know where to connect to your microservice internally:

```ruby
if ENV['OPENC3_OPERATOR_HOSTNAME']
  url = "http://#{ENV['OPENC3_OPERATOR_HOSTNAME']}:#{port}"
else
  if ENV['KUBERNETES_SERVICE_HOST']
    url = "http://#{microservice_name.downcase.gsub('__', '-').gsub('_', '-')}-service:#{port}"
  else
    url = "http://openc3-operator:#{port}"
  end
end
```

Note that this is the internal route to your microservice. Determining this route checks two different environment variables.

OPENC3_OPERATOR_HOSTNAME is used to override the default service name for our regular docker compose operator of "openc3-operator". Usually this is not set.

In OpenC3 Enterprise, KUBERNETES_SERVICE_HOST is used to detect if we are running in a Kubernetes environment (it will be set by Kubernetes), in which case the service is expected to have a Kubernetes service named scope-user-microservicename-service. For example, if you are using the DEFAULT scope and have a microservice named MYMICROSERVICE the service would be found at the hostname: default-user-mymicroservice-service. Double underscores or single underscores are replaced by a dash and the name is all lower case.

[ROUTE_PREFIX](../configuration/plugins#route_prefix-1) is used to define the external route. The external route will take the form of http(s)://YOURCOSMOSDOMAIN:PORT/ROUTE_PREFIX. So for example, if you set the [ROUTE_PREFIX](../configuration/plugins#route_prefix-1) to /mymicroservice then on a default local installation, it could be reached at `http://localhost:2900/mymicroservice`. The `http://localhost:2900` part should be substituted by whatever domain you are accessing COSMOS at.

Here is a snippet of code showing [PORT](../configuration/plugins#port-1) and [ROUTE_PREFIX](../configuration/plugins#route_prefix-1) in use within a plugin.txt file:

```bash
VARIABLE cfdp_microservice_name CFDP
VARIABLE cfdp_route_prefix /cfdp
VARIABLE cfdp_port 2905

MICROSERVICE CFDP <%= cfdp_microservice_name %>
  WORK_DIR .
  ROUTE_PREFIX <%= cfdp_route_prefix %>
  PORT <%= cfdp_port %>
```

Leaving the variables at their default values the following will occur:

- The microservice will be exposed internally to Docker (Open Source or Enterprise) at: `http://openc3-operator:2905`
- The microservice will be exposed internally to Kubernetes (Enterprise) at: `http://default-user-cfdp-service:2905`
- The microservice will be exposed externally to the network at: `http://localhost:2900/cfdp`

The same can be done for [INTERFACE](../configuration/plugins#interface-1) but note that the Kubernetes service name will use the microservice name of the interface which takes the form of `SCOPE__INTERFACE__INTERFACENAME`.

Here is an example using [PORT](../configuration/plugins#port) and [ROUTE_PREFIX](../configuration/plugins#route_prefix) with [INTERFACE](../configuration/plugins#interface-1):

```bash
VARIABLE my_interface_name MY_INT
VARIABLE my_route_prefix /myint
VARIABLE my_port 2910

INTERFACE <%= my_interface_name %> http_server_interface.rb <%= my_port %>
  ROUTE_PREFIX <%= my_route_prefix %>
  PORT <%= my_port %>
```

- The interface will be exposed internally to Docker (Open Source or Enterprise) at: `http://openc3-operator:2910`
- The interface will be exposed internally to Kubernetes (Enterprise) at: `http://default-interface-my-int-service:2905`
- The interface will be exposed externally to the network at: `http://localhost:2900/myint`

:::warning Sharded Operator on Kubernetes (Enterprise)

The sharded operator is expected to be used on Kubernetes whenever the Kubernetes Operator is not used. Typically this will be because the user does not have permission to use the Kubernetes API directly to spawn containers which is required for use of the Kubernetes Operator. In this case, Kubernetes services will NOT be automatically created, and will have to be manually created by a user with permissions in Kubernetes, or through some other authorized method (like a custom framework dashboard or config file).
:::

## Connecting to microservices from a different INTERFACE in plugin.txt

Sometimes you might want to have an INTERFACE connect to a microservice you are running. For this case, only the PORT keyword is required on the INTERFACE or MICROSERVICE because we are only connecting internally and ROUTE_PREFIX isn't used.

The following code taken from our demo plugin provides an example of how to calculate the correct hostname across both Open Source and Enterprise versions of COSMOS in a plugin.txt file:

```
  <% example_host = ENV['KUBERNETES_SERVICE_HOST'] ? "#{scope}-user-#{example_microservice_name.downcase.gsub('__', '-').gsub('_', '-')}-service" : "openc3-operator" %>
  INTERFACE <%= example_int_name %> example_interface.rb <%= example_host %> <%= example_port %>
    MAP_TARGET <%= example_target_name %>
```

Note that the above code does not handle the OPENC3_OPERATOR_HOSTNAME environment variable which might change the default name of openc3-operator. Update as needed.
