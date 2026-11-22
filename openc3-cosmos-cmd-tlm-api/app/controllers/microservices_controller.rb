# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/models/microservice_model'

class MicroservicesController < ModelController
  def initialize
    super()
    @model_class = OpenC3::MicroserviceModel
  end

  # Override show to include computed runtime_python_env field.
  # This is NOT stored in as_json (which is used for Redis persistence)
  # to avoid breaking from_json deserialization.
  def show
    return unless authorization('system')
    if params[:id].downcase == 'all'
      render json: @model_class.all(scope: params[:scope])
    else
      model = @model_class.get_model(name: params[:id], scope: params[:scope])
      if model
        render json: model.as_json.merge('runtime_python_env' => model.runtime_python_env)
      else
        head :not_found
      end
    end
  rescue StandardError => error
    render json: { status: 'error', message: error.message }, status: :internal_server_error
    logger.error(error.formatted)
  end

  def start
    return unless authorization('admin')
    microservice = @model_class.get_model(name: params[:id], scope: params[:scope])
    if microservice
      OpenC3::Logger.info("#{params[:id]} started", scope: params[:scope], user: username())
      microservice.enabled = true
      microservice.update
    end
    head :ok
  end

  def stop
    return unless authorization('admin')
    microservice = @model_class.get_model(name: params[:id], scope: params[:scope])
    if microservice
      OpenC3::Logger.info("#{params[:id]} stopped", scope: params[:scope], user: username())
      microservice.enabled = false
      microservice.update
    end
    head :ok
  end

  # Microservice routes sit below every built in traefik router except files (3),
  # base (2) and web (1). Their prefixes can't overlap /files (it is reserved),
  # and they must win over base and web so a microservice can serve paths with
  # a file extension.
  ROUTER_PRIORITY = 3
  ROUTER_NAME_REGEX = /\A[A-Za-z0-9_\-]+\z/

  # Dynamic configuration for traefik's http provider, which polls this directly
  # on the internal network. No authentication because traefik can't send any.
  def traefik
    # Requests routed through traefik have X-Forwarded-For set. The route
    # table is only used by traefik's provider so don't serve it externally.
    if request.headers['X-Forwarded-For'] or request.headers['X-Real-Ip']
      head :not_found
      return
    end

    routers = {}
    services = {}
    models = OpenC3::MicroserviceModel.all
    models.each do |microservice_name, microservice|
      prefix = microservice['prefix']
      ports = microservice['ports']
      if prefix and ports and ports[0] and ports[0][0]
        # Microservices stored before prefixes were validated may still be in Redis
        unless ROUTER_NAME_REGEX.match?(microservice_name)
          logger.warn("Not routing microservice #{microservice_name.inspect}: invalid name")
          next
        end
        begin
          prefix = OpenC3::MicroserviceModel.validate_route_prefix(prefix)
        rescue RuntimeError => error
          logger.warn("Not routing microservice #{microservice_name}: #{error.message}")
          next
        end
        port = ports[0][0].to_i
        shard = microservice['shard'] || 0
        if ENV['OPENC3_OPERATOR_HOSTNAME']
          if shard != 0
            url = "http://#{ENV.fetch('OPENC3_OPERATOR_HOSTNAME')}-#{shard}:#{port}"
          else
            url = "http://#{ENV.fetch('OPENC3_OPERATOR_HOSTNAME')}:#{port}"
          end
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
        # PathPrefix is a plain string prefix (/api would also match /apix), so
        # match the prefix itself or anything below it
        routers[router_name]['rule'] = "Path(`#{prefix}`) || PathPrefix(`#{prefix}/`)"
        routers[router_name]['service'] = service_name
        routers[router_name]['priority'] = ROUTER_PRIORITY
      end
    end
    if routers.empty?
      # Traefik rejects empty routers and services maps as "standalone elements"
      # and then keeps its previous configuration, leaving deleted routes live.
      # An empty object is accepted and clears them.
      render json: {}
    else
      render json: { 'http' => { 'routers' => routers, 'services' => services } }
    end
  end
end
