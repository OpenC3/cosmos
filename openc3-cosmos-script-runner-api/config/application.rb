require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
# require "active_job/railtie"
# require "active_record/railtie"
# require "active_storage/engine"
require "action_controller/railtie"
# require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
# require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

require 'prometheus/client/data_stores/direct_file_store'
Prometheus::Client.config.data_store = Prometheus::Client::DataStores::DirectFileStore.new(dir: "tmp/metrics")

module ScriptRunnerApi
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.0
    # Add to hosts to prevent "Blocked host" errors
    config.hosts.clear

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    config.action_cable.disable_request_forgery_protection = true
    config.action_cable.mount_path = '/script-api/cable'

    OpenC3::Logger.microservice_name = 'SCRIPT__RUNNER__API'

    require 'openc3/utilities/open_telemetry'
    OpenC3.setup_open_telemetry('SCRIPT__RUNNER__API', true)
    if OpenC3.otel_enabled
      config.middleware.insert_before(
        0,
        OpenTelemetry::Instrumentation::Rack::Middlewares::TracerMiddleware
      )
    end

    puts "Starting #{$0} in #{Rails.env} environment"

    # Setup structured logging
    require 'openc3/utilities/cosmos_rails_formatter'
    # Don't set the anycable logger to info because it's way too much output
    if $0.include?('anycable')
      config.log_level = ENV["LOG_LEVEL"] || :error
    else
      config.log_level = ENV["LOG_LEVEL"] || :info
    end
    config.log_tags = {
      request_id: :request_id,
      token: -> request { request.headers['HTTP_AUTHORIZATION'] || request.query_parameters[:authorization] }
    }
    config.rails_semantic_logger.add_file_appender = false
    config.semantic_logger.add_appender(
      io: $stdout,
      formatter: OpenC3::CosmosRailsFormatter.new
    )
  end
end
