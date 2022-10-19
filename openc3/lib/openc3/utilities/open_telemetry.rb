# encoding: ascii-8bit

# Copyright 2022 OpenC3, Inc.
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

require 'openc3/utilities/bucket'

module OpenC3
  @otel_enabled = false

  def self.otel_enabled
    @otel_enabled
  end

  def self.inject_context(hash)
    if @otel_enabled
      OpenTelemetry.propagation.inject(hash)
    end
  end

  def self.with_context(hash)
    if @otel_enabled
      extracted_context = OpenTelemetry.propagation.extract(hash)
      OpenTelemetry::Context.with_current(extracted_context) do
        yield
      end
    else
      yield
    end
  end

  def self.in_span(span_name, tracer_name = 'openc3-tracer')
    if @otel_enabled
      tracer = OpenTelemetry.tracer_provider.tracer(tracer_name)
      tracer.in_span(span_name) do |span|
        yield span
      end
    else
      yield nil
    end
  end

  def self.setup_open_telemetry(service_name, support_rails = false)
    if ENV['OTEL_EXPORTER_OTLP_ENDPOINT']
      split_services = ENV['OPENC3_OTEL'].to_s.split(',')
      @otel_enabled = true if split_services.include?(service_name) or split_services.include?('ALL')

      if @otel_enabled
        require 'redis'
        require 'httpclient'
        require 'openc3/utilities/bucket'
        # Load the bucket client code so the instrumentation works later
        Bucket.getClient()
        require 'opentelemetry/sdk'
        require 'opentelemetry/exporter/otlp'
        require 'opentelemetry/instrumentation/redis'
        require 'opentelemetry/instrumentation/http_client'
        require 'opentelemetry/instrumentation/aws_sdk'
        if support_rails
          require 'opentelemetry/instrumentation/rack'
          require 'opentelemetry/instrumentation/action_pack'
        end
        OpenTelemetry::SDK.configure do |c|
          c.service_name = service_name
          if support_rails
            c.use('OpenTelemetry::Instrumentation::Rack')
            c.use('OpenTelemetry::Instrumentation::ActionPack', { enable_recognize_route: true })
          end
          c.use 'OpenTelemetry::Instrumentation::Redis', {
            # The obfuscation of arguments in the db.statement attribute is enabled by default.
            # To include the full query, set db_statement to :include.
            # To obfuscate, set db_statement to :obfuscate.
            # To omit the attribute, set db_statement to :omit.
            db_statement: :include,
          }
          c.use 'OpenTelemetry::Instrumentation::HttpClient'
          c.use 'OpenTelemetry::Instrumentation::AwsSdk'
          # TODO: Add in additional cloud SDKs
        end
      end
    end
  end
end
