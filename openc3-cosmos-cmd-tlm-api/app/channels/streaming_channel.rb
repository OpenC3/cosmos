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

class StreamingChannel < ApplicationCable::Channel
  @@broadcasters = {}

  def subscribed
    # Defensive: if the auth before_subscribe callback rejected us, skip work.
    return if subscription_rejected?
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
    subscription_key = "streaming_#{uuid}"
    if validate_data(data)
      begin
        # Nil-guard the broadcaster: it only exists between `subscribed` (which
        # skips creation when the auth callback rejected us) and `unsubscribed`.
        # A perform that races a rejected/torn-down subscription would otherwise
        # raise NoMethodError here, get rescued below, and reject_subscription —
        # killing every panel on the connection. A no-op is the correct response;
        # the client re-subscribes and replays its adds.
        @@broadcasters[subscription_key]&.add(data)
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
    subscription_key = "streaming_#{uuid}"
    if validate_data(data)
      begin
        # Nil-guard the broadcaster (see `add`): a `remove` that races a
        # rejected/torn-down subscription must be a harmless no-op, not a
        # NoMethodError that reject_subscription()s every panel on the connection.
        @@broadcasters[subscription_key]&.remove(data)
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
