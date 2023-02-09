# encoding: ascii-8bit

# Copyright 2023 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/utilities/store'

module OpenC3
  class TraefikModel
    def self.register_route(microservice_name:, port:, prefix:, priority: 20)
      prefix = '/' + prefix unless prefix[0] == '/'
      if ENV['KUBERNETES_SERVICE_HOST']
        url = "http://#{microservice_name.gsub('__', '-')}:#{port}"
      else
        url = "http://openc3-operator:#{port}"
      end
      service_name = microservice_name
      router_name = microservice_name
      Store.set("traefik/http/services/#{service_name}/loadbalancer/servers/0/url", url)
      Store.set("traefik/http/routers/#{router_name}/service", service_name)
      Store.set("traefik/http/routers/#{router_name}/priority", priority)
      Store.set("traefik/http/routers/#{router_name}/rule", "PathPrefix(`#{prefix}`)")
    end

    def self.unregister_route(microservice_name:)
      service_name = microservice_name
      router_name = microservice_name
      Store.del("traefik/http/routers/#{router_name}/rule")
      Store.del("traefik/http/routers/#{router_name}/priority")
      Store.del("traefik/http/routers/#{router_name}/service")
      Store.del("traefik/http/services/#{service_name}/loadbalancer/servers/0/url")
    end
  end
end
