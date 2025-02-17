# encoding: ascii-8bit

# Copyright 2025 OpenC3, Inc.
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

require 'openc3/microservices/microservice'
require 'openc3/models/offline_access_model'
require 'openc3/models/news_model'
# The VERSION and ENTERPRISE constants are set by settings_api.rb
require 'openc3/api/settings_api'

module OpenC3
  class PeriodicMicroservice < Microservice
    include Api

    STARTUP_DELAY_SECONDS = 2 * 60 # Two Minutes
    SLEEP_PERIOD_SECONDS = 24 * 60 * 60 # Run once per day

    def initialize(*args)
      super(*args)
      @metric.set(name: 'periodic_total', value: @count, type: 'counter')
      @conn = nil # Faraday connection set by get_news
      get_news()
    end

    def get_news
      if get_setting('news_feed', scope: @scope)
        unless @conn
          @conn = Faraday.new(
            url: 'https://news.openc3.com',
            params: {version: VERSION, enterprise: ENTERPRISE},
          )
        end
        response = @conn.get('/news')
        if response.success?
          NewsModel.set(response.body)
        else
          NewsModel.news_error(response)
        end
      end
    end

    def run
      @run_sleeper = Sleeper.new
      return if @run_sleeper.sleep(STARTUP_DELAY_SECONDS)
      while true
        models = OfflineAccessModel.get_all_models(scope: @scope)
        models.each do |name, model|
          if model.offline_access_token
            auth = OpenC3KeycloakAuthentication.new(ENV['OPENC3_KEYCLOAK_URL'])
            valid_token = auth.get_token_from_refresh_token(model.offline_access_token)
            if valid_token
              @logger.info("Refreshed offline access token for #{name}")
              model.offline_access_token = auth.refresh_token
            else
              @logger.error("Unable to refresh offline access token for #{name}")
              model.offline_access_token = nil
            end
            model.update
          end
        end
        @count += 1
        @metric.set(name: 'periodic_total', value: @count, type: 'counter')
        break if @cancel_thread
        break if @run_sleeper.sleep(SLEEP_PERIOD_SECONDS)
        get_news()
      end
    end

    def shutdown
      @run_sleeper.cancel if @run_sleeper
      super()
    end
  end
end

OpenC3::PeriodicMicroservice.run if __FILE__ == $0
