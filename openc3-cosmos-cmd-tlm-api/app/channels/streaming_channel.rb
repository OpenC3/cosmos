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

class StreamingChannel < ApplicationCable::Channel
  @@broadcasters = {}

  def subscribed
    subscription_key = "streaming_#{uuid}"
    stream_from subscription_key
    @@broadcasters[subscription_key] = StreamingApi.new(subscription_key, scope: scope)
  end

  def unsubscribed
    subscription_key = "streaming_#{uuid}"
    if @@broadcasters[subscription_key]
      stop_stream_from subscription_key
      @@broadcasters[subscription_key].kill
      @@broadcasters[subscription_key] = nil
      @@broadcasters.delete(subscription_key)
    end
  end

  # data holds the following keys:
  #   start_time - nsec_since_epoch - null for realtime
  #   end_time - nsec_since_epoch - null for realtime or continue to realtime
  #   items [Array of Item keys] ie ["DECOM__TLM__INST__ADCS__Q1__RAW"]
  #   scope
  def add(data)
    if validate_data(data)
      begin
        @@broadcasters[uuid].add(data)
      rescue OpenC3::AuthError, OpenC3::ForbiddenError
        transmit({ "error" => "unauthorized" })
        reject() # Sets the rejected state on the connection
        reject_subscription() # Calls the 'rejected' method on the frontend
      rescue => err
        transmit({ "error" => "#{err.class}:#{err.message}" })
        reject() # Sets the rejected state on the connection
        reject_subscription() # Calls the 'rejected' method on the frontend
      end
    end
  end

  # data holds the following keys:
  #   items [Array of Item keys] ie ["DECOM__TLM__INST__ADCS__Q1__RAW"]
  #   scope
  def remove(data)
    if validate_data(data)
      begin
        @@broadcasters[uuid].remove(data)
      rescue OpenC3::AuthError, OpenC3::ForbiddenError
        transmit({ "error" => "unauthorized" })
        reject() # Sets the rejected state on the connection
        reject_subscription() # Calls the 'rejected' method on the frontend
      rescue => err
        transmit({ "error" => "#{err.class}:#{err.message}" })
        reject() # Sets the rejected state on the connection
        reject_subscription() # Calls the 'rejected' method on the frontend
      end
    end
  end

  private

  def validate_data(data)
    result = true
    unless data['scope']
      transmit({ "error" => "scope is required" })
      reject() # Sets the rejected state on the connection
      reject_subscription() # Calls the 'rejected' method on the frontend
      result = false
    end
    result
  end
end
