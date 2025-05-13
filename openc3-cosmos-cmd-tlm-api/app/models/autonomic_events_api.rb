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
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require_relative 'topics_thread'

class AutonomicEventsApi
  def initialize(subscription_key, history_count = 0, scope:)
    topics = ["#{scope}__openc3_autonomic"] # MUST be equal to `AutonomicTopic::PRIMARY_KEY`
    @thread = TopicsThread.new(topics, subscription_key, history_count)
    @thread.start
  end

  def kill
    @thread.stop
  end
end