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

require 'openc3/io/json_api_object'
require 'openc3/utilities/authentication'

module OpenC3
  class JsonApi
    # Create a JsonApiObject connection to the API server
    def initialize(microservice_name:, prefix:, schema: 'http', hostname: nil, port:, timeout: 5.0, url: nil, scope: $openc3_scope)
      url = _generate_url(microservice_name: microservice_name, prefix: prefix, schema: schema, hostname: hostname, port: port, scope: scope) unless url
      @json_api = JsonApiObject.new(
        url: url,
        timeout: timeout,
        authentication: _generate_auth()
      )
    end

    def shutdown
      @json_api.shutdown
    end

    # private

    # pull openc3-cosmos-script-runner-api url from environment variables
    def _generate_url(microservice_name:, prefix:, schema: 'http', hostname: nil, port:, scope: $openc3_scope)
      prefix = '/' + prefix unless prefix[0] == '/'
      if ENV['OPENC3_OPERATOR_HOSTNAME']
        hostname = ENV['OPENC3_OPERATOR_HOSTNAME'] unless hostname
        return "#{schema}://#{hostname}:#{port.to_i}#{prefix}"
      else
        if ENV['KUBERNETES_SERVICE_HOST']
          hostname = "#{scope}__USER__#{microservice_name}" unless hostname
          hostname = hostname.downcase.gsub("__", "-").gsub("_", "-")
          return "#{schema}://#{hostname}-service:#{port.to_i}#{prefix}"
        else
          hostname = 'openc3-operator' unless hostname
          return "#{schema}://#{hostname}:#{port.to_i}#{prefix}"
        end
      end
    end

    # generate the auth object
    def _generate_auth
      if ENV['OPENC3_API_TOKEN'].nil? and ENV['OPENC3_API_USER'].nil?
        if ENV['OPENC3_API_PASSWORD']
          return OpenC3Authentication.new()
        else
          return nil
        end
      else
        return OpenC3KeycloakAuthentication.new(ENV['OPENC3_KEYCLOAK_URL'])
      end
    end

    def _request(*method_params, **kw_params)
      kw_params[:scope] = $openc3_scope unless kw_params[:scope]
      kw_params[:json] = true unless kw_params[:json]
      @json_api.request(*method_params, **kw_params)
    end
  end
end
