# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

# anycable-go's gRPC client sends keepalive pings every 10s (hardcoded in
# keepalive.ClientParameters.Time). AnyCable's default server enforcement
# (min_recv_ping_interval_without_data_ms = 10_000) matches the client
# exactly, so normal scheduling jitter can make a ping arrive just under the
# threshold and accumulate strikes until the server emits
# GoAway ENHANCE_YOUR_CALM "too_many_pings", tearing down active RPCs.
# Halving the server minimum gives 5s of jitter tolerance against the fixed
# 10s client interval. See grpc/grpc#25713 and doc/keepalive.md.
AnyCable.configure do |config|
  config.rpc_server_args = {
    "grpc.keepalive_permit_without_calls" => 1,
    "grpc.http2.min_recv_ping_interval_without_data_ms" => 5_000,
    "grpc.http2.min_ping_interval_without_data_ms" => 5_000,
  }
end
