# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
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

# Modified by OpenC3, Inc.
# All changes Copyright 2024, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/models/microservice_model'

class MicroservicesController < ModelController
  def initialize
    @model_class = OpenC3::MicroserviceModel
  end

  def traefik
    result = {}
    result['http'] = {}
    http = result['http']
    http['routers'] = {}
    routers = http['routers']
    http['services'] = {}
    services = http['services']
    models = OpenC3::MicroserviceModel.all
    models.each do |microservice_name, microservice|
      prefix = microservice['prefix']
      ports = microservice['ports']
      if prefix and ports[0][0]
        port = ports[0][0].to_i
        prefix = '/' + prefix unless prefix[0] == '/'
        if ENV['OPENC3_OPERATOR_HOSTNAME']
          url = "http://#{ENV['OPENC3_OPERATOR_HOSTNAME']}:#{port}"
        else
          if ENV['KUBERNETES_SERVICE_HOST']
            url = "http://#{microservice_name.downcase.gsub('__', '-').gsub('_', '-')}-service:#{port}"
          else
            url = "http://openc3-operator:#{port}"
          end
        end
        service_name = microservice_name
        router_name = microservice_name
        services[service_name] = {}
        services[service_name]['loadBalancer'] = {}
        services[service_name]['loadBalancer']['passHostHeader'] = false
        services[service_name]['loadBalancer']['servers'] = []
        services[service_name]['loadBalancer']['servers'] << {"url" => url}
        routers[router_name] = {}
        routers[router_name]['rule'] = "PathPrefix(`#{prefix}`)"
        routers[router_name]['service'] = service_name
        routers[router_name]['priority'] = 20
      end
    end
    render json: result
  end
end
