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

require 'openc3/microservices/microservice'
require 'openc3/topics/topic'

module OpenC3
  class PluginMicroservice < Microservice
    def initialize(name)
      super(name, is_plugin: true)
    end

    def run
      Dir.chdir @work_dir
      begin
        if @config["cmd"][0] != 'ruby'
          # Try to make sure the cmd is executable
          FileUtils.chmod 0777, @config["cmd"][0]
        end
      rescue Exception
        # Its ok if this fails
      end

      # exec() below replaces this process image, so the Metric update thread
      # this bootstrap started dies without ever running shutdown. Whatever it
      # managed to publish would then sit in Redis untouched until it expired,
      # looking for all the world like a live microservice pinned at whatever
      # cpu the bootstrap itself burned loading the OpenC3 gem. Clear it out and
      # stop the thread before handing the process over to the real cmd. A cmd
      # that is itself an OpenC3::Microservice builds a new Metric and starts
      # publishing again; one that isn't gets its cpu and memory reported by the
      # operator instead (see Operator#publish_process_metrics).
      begin
        @metric.shutdown
        MetricModel.new(name: @name, scope: @scope).destroy
      rescue Exception => e
        @logger.warn("Failed to clear bootstrap metrics for #{@name}: #{e.message}")
      end

      # Fortify: Process Control
      # This is dangerous! However, plugins need to be able to run whatever they want.
      # Only admins can install plugins and they need to be vetted for content.
      # NOTE: In Enterprise each microservice gets its own container so the potential
      # footprint is much smaller. In Core you're in the same container
      # as all the other plugins.
      exec(*@config["cmd"])
    end
  end
end

OpenC3::PluginMicroservice.run if __FILE__ == $0
