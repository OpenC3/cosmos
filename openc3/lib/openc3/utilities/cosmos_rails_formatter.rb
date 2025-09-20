require "json"
require 'openc3/utilities/logger'
require 'openc3/utilities/authorization'

# Use with Rails Semantic Logger
module OpenC3
  class CosmosRailsFormatter
    include OpenC3::Authorization

    def call(log, _appender = nil)
      #<SemanticLogger::Log:0x0000ffffa5002b20 @level=:info, @thread_name="puma srv tp 001", @name="MicroservicesController",
      # @time=2024-09-22 18:04:27.955490052 +0000, @tags=[], @named_tags={}, @level_index=2, @message="Completed #traefik",
      # @payload={:controller=>"MicroservicesController", :action=>"traefik", :format=>"HTML", :method=>"GET",
      # :path=>"/openc3-api/traefik", :status=>200, :view_runtime=>0.41, :allocations=>1438, :status_message=>"OK",
      # :exception_object=>#<RuntimeError: death>}, @named_tags={:request_id=>"65446ef0-734e-4488-aa5f-e85b7b573fd8"},
      # @duration=3.2528750002384186, @metric=nil, @metric_amount=nil, @dimensions=nil, @exception=nil, @backtrace=nil>
      message = log.message
      other = {}
      other[:thread_name] = log.thread_name
      other[:duration] = log.duration if log.duration
      named_tags = log.named_tags
      username = nil
      if named_tags
        other[:request_id] = named_tags[:request_id]
        if named_tags[:token]
          begin
            user = user_info(named_tags[:token])
          rescue
            user = {}
          end
          username = user['username']
          # Core username (Enterprise has the actual username)
          username ||= 'anonymous'
        end
      end
      username ||= 'anonymous'
      payload = log.payload
      if payload
        other[:path] = payload[:path]
        other[:status] = payload[:status]
        other[:controller] = payload[:controller]
        other[:action] = payload[:action]
        other[:format] = payload[:format]
        other[:method] = payload[:method]
        other[:allocations] = payload[:allocations]
        other[:view_runtime] = payload[:view_runtime]
        if payload[:exception_object]
          other[:exception_message] = payload[:exception_object].message
          other[:exception_class] = payload[:exception_object].class.to_s
          other[:exception_backtrace] = payload[:exception_object].backtrace.as_json
        end
      end
      # This happens for a separate exception log entry which we want to not include the backtrace a second time
      if log.exception
        message = "Exception was raised - #{log.exception.class}:#{log.exception.message}" unless message
      end
      return OpenC3::Logger.build_log_data(log.level.to_s.upcase, message, user: username, type: OpenC3::Logger::LOG, url: nil, other: other).as_json().to_json(allow_nan: true)
    end
  end
end
