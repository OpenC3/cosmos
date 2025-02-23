# encoding: ascii-8bit

# Copyright 2024 OpenC3 Inc.
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
require 'openc3/topics/topic'
require 'openc3/utilities/thread_manager'

module OpenC3
  class MultiMicroservice < Microservice
    def run
      ARGV.each do |microservice_name|
        microservice_model = MicroserviceModel.get_model(name: microservice_name, scope: @scope)
        if microservice_model.enabled
          thread = Thread.new do
            cmd_line = microservice_model.cmd.join(' ')
            split_cmd_line = cmd_line.split(' ')
            filename = nil
            split_cmd_line.each do |item|
              if File.extname(item) == '.rb'
                filename = item
                break
              end
            end
            raise "Could not determine class filename from '#{cmd_line}'" unless filename
            OpenC3.set_working_dir(microservice_model.work_dir) do
              require File.join(microservice_model.work_dir, filename)
            end
            klass = filename.filename_to_class_name.to_class
            klass.run(microservice_model.name)
          end
          ThreadManager.instance.register(thread)
        end
      end
      ThreadManager.instance.monitor
      ThreadManager.instance.shutdown
    end
  end
end
if __FILE__ == $0
  OpenC3::MultiMicroservice.run
  ThreadManager.instance.shutdown
  ThreadManager.instance.join
end