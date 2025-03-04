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
# All changes Copyright 2025, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

# Provides a demonstration of a Simulated Target

require 'openc3'
require 'stringio'
require 'base64'
require 'openc3/accessors/binary_accessor'

module OpenC3
  # Simulated instrument for the demo. Populates several packets and cycles
  # the telemetry to simulate an active target.
  class SimInst < SimulatedTarget
    SOLAR_PANEL_DFLTS = [-179.0, 179.0, -179.0, 179.0, -95.0] unless defined? SOLAR_PANEL_DFLTS

    def initialize(target_name)
      super(target_name)

      @target = System.targets[target_name]
      position_filename = File.join(@target.dir, 'data', 'position.bin')
      attitude_filename = File.join(@target.dir, 'data', 'attitude.bin')
      position_data = File.read(position_filename, mode: "rb")
      attitude_data = File.read(attitude_filename, mode: "rb")
      @position_file = StringIO.new(position_data)
      @position_file_size = position_data.length
      @attitude_file = StringIO.new(attitude_data)
      @attitude_file_size = attitude_data.length
      @position_file_bytes_read = 0
      @attitude_file_bytes_read = 0

      @images = []
      data = File.read(File.join(@target.dir, 'public', 'spiral.jpg'), mode: "rb")
      @images << Base64.encode64(data)
      data = File.read(File.join(@target.dir, 'public', 'sun.jpg'), mode: "rb")
      @images << Base64.encode64(data)
      data = File.read(File.join(@target.dir, 'public', 'ganymede.jpg'), mode: "rb")
      @images << Base64.encode64(data)
      @cur_image = 0

      @pos_packet = Structure.new(:BIG_ENDIAN)
      @pos_packet.append_item('DAY', 16, :UINT)
      @pos_packet.append_item('MSOD', 32, :UINT)
      @pos_packet.append_item('USOMS', 16, :UINT)
      @pos_packet.append_item('POSX', 32, :FLOAT)
      @pos_packet.append_item('POSY', 32, :FLOAT)
      @pos_packet.append_item('POSZ', 32, :FLOAT)
      @pos_packet.append_item('SPARE1', 16, :UINT)
      @pos_packet.append_item('SPARE2', 32, :UINT)
      @pos_packet.append_item('SPARE3', 16, :UINT)
      @pos_packet.append_item('VELX', 32, :FLOAT)
      @pos_packet.append_item('VELY', 32, :FLOAT)
      @pos_packet.append_item('VELZ', 32, :FLOAT)
      @pos_packet.append_item('SPARE4', 32, :UINT)
      @pos_packet.enable_method_missing

      @att_packet = Structure.new(:BIG_ENDIAN)
      @att_packet.append_item('DAY', 16, :UINT)
      @att_packet.append_item('MSOD', 32, :UINT)
      @att_packet.append_item('USOMS', 16, :UINT)
      @att_packet.append_item('Q1', 32, :FLOAT)
      @att_packet.append_item('Q2', 32, :FLOAT)
      @att_packet.append_item('Q3', 32, :FLOAT)
      @att_packet.append_item('Q4', 32, :FLOAT)
      @att_packet.append_item('BIASX', 32, :FLOAT)
      @att_packet.append_item('BIASY', 32, :FLOAT)
      @att_packet.append_item('BIASZ', 32, :FLOAT)
      @att_packet.append_item('SPARE', 32, :FLOAT)
      @att_packet.enable_method_missing

      packet = @tlm_packets['HEALTH_STATUS']
      packet.enable_method_missing
      packet.CcsdsSeqFlags = 'NOGROUP'
      packet.CcsdsLength = packet.buffer.length - 7
      packet.temp1 = 50.0
      packet.temp2 = -20.0
      packet.temp3 = 85.0
      packet.temp4 = 0.0
      packet.duration = 10.0
      packet.collect_type = 'NORMAL'

      packet = @tlm_packets['ADCS']
      packet.enable_method_missing
      packet.CcsdsSeqFlags = 'NOGROUP'
      packet.CcsdsLength   = packet.buffer.length - 7

      packet = @tlm_packets['PARAMS']
      packet.enable_method_missing
      packet.CcsdsSeqFlags = 'NOGROUP'
      packet.CcsdsLength = packet.buffer.length - 7
      packet.value1 = 0
      packet.value2 = 1
      packet.value3 = 2
      packet.value4 = 1
      packet.value5 = 0
      packet.write('P_2.2,2', BinaryAccessor::MIN_INT64)
      packet.write('P-3+3=3', BinaryAccessor::MAX_INT64)
      packet.write('P4!@#$%^&*?', 0)
      packet.write('P</5|\>', 1740684371613049856)
      packet.write('P(:6;)', BinaryAccessor::MAX_UINT64)

      packet = @tlm_packets['IMAGE']
      packet.enable_method_missing
      packet.CcsdsSeqFlags = 'NOGROUP'
      packet.CcsdsLength = packet.buffer.length - 7

      packet = @tlm_packets['MECH']
      packet.enable_method_missing
      packet.CcsdsSeqFlags = 'NOGROUP'
      packet.CcsdsLength = packet.buffer.length - 7

      packet = @tlm_packets['HIDDEN']
      packet.enable_method_missing
      packet.CcsdsSeqFlags = 'NOGROUP'
      packet.CcsdsLength = packet.buffer.length - 7

      @solar_panel_positions = SOLAR_PANEL_DFLTS.dup
      @solar_panel_thread = nil
      @solar_panel_thread_cancel = false

      @track_stars = Array.new
      @track_stars[0] = 1237
      @track_stars[1] = 1329
      @track_stars[2] = 1333
      @track_stars[3] = 1139
      @track_stars[4] = 1161
      @track_stars[5] = 682
      @track_stars[6] = 717
      @track_stars[7] = 814
      @track_stars[8] = 583
      @track_stars[9] = 622

      @bad_temp2 = false
      @last_temp2 = 0
      @quiet = false
      @time_offset = 0
      @ip_address = 0
    end

    def set_rates
      set_rate('ADCS', 10)
      set_rate('HEALTH_STATUS', 100)
      set_rate('PARAMS', 100)
      set_rate('IMAGE', 100)
      set_rate('MECH', 10)
      set_rate('HIDDEN', 500)
    end

    def tick_period_seconds
      return 0.1 # Override this method to optimize
    end

    def tick_increment
      return 10 # Override this method to optimize
    end

    def write(packet)
      name = packet.packet_name.upcase

      hs_packet = @tlm_packets['HEALTH_STATUS']
      params_packet = @tlm_packets['PARAMS']

      case name
      when 'COLLECT'
        hs_packet.cmd_acpt_cnt += 1
        hs_packet.collects += 1
        hs_packet.duration = packet.read('duration')
        hs_packet.collect_type = packet.read("type")
      when 'ABORT', 'FLTCMD', 'ARYCMD'
        hs_packet.cmd_acpt_cnt += 1
      when 'CLEAR'
        hs_packet.cmd_acpt_cnt = 0
        hs_packet.collects = 0
      when 'SETPARAMS'
        hs_packet.cmd_acpt_cnt += 1
        params_packet.value1 = packet.read('value1')
        params_packet.value2 = packet.read('value2')
        params_packet.value3 = packet.read('value3')
        params_packet.value4 = packet.read('value4')
        params_packet.value5 = packet.read('value5')
        params_packet.write('P4!@#$%^&*?', packet.read('bigint'))
      when 'ASCIICMD'
        hs_packet.cmd_acpt_cnt += 1
        hs_packet.asciicmd = packet.read('string')
      when 'SLRPNLDEPLOY'
        hs_packet.cmd_acpt_cnt += 1
        return if @solar_panel_thread and @solar_panel_thread.alive?
        @solar_panel_thread = Thread.new do
          @solar_panel_thread_cancel = false
          (0..@solar_panel_positions.size - 1).to_a.reverse_each do |i|
            while (@solar_panel_positions[i] > 0.1) or (@solar_panel_positions[i] < - 0.1)
              if @solar_panel_positions[i] > 3.0
                @solar_panel_positions[i] -= 3.0
              elsif @solar_panel_positions[i] < -3.0
                @solar_panel_positions[i] += 3.0
              else
                @solar_panel_positions[i] = 0.0
              end
              sleep(0.10)
              break if @solar_panel_thread_cancel
            end
            if @solar_panel_thread_cancel
              @solar_panel_thread_cancel = false
              break
            end
          end
        end
      when 'SLRPNLRESET'
        hs_packet.cmd_acpt_cnt += 1
        OpenC3.kill_thread(self, @solar_panel_thread)
        @solar_panel_positions = SOLAR_PANEL_DFLTS.dup
      when 'MEMLOAD'
        hs_packet.cmd_acpt_cnt += 1
        hs_packet.blocktest = packet.read('data')
      when 'QUIET'
        hs_packet.cmd_acpt_cnt += 1
        if packet.read('state') == 'TRUE'
          @quiet = true
        else
          @quiet = false
        end
      when 'TIME_OFFSET'
        hs_packet.cmd_acpt_cnt += 1
        @time_offset = packet.read('seconds')
        @ip_address = packet.read('ip_address')
      when 'HIDDEN'
        # Deliberately do not increment cmd_acpt_cnt
        @tlm_packets['HIDDEN'].count = packet.read('count')
      end
    end

    def graceful_kill
      @solar_panel_thread_cancel = true
    end

    def read(count_100hz, time)
      pending_packets = get_pending_packets(count_100hz)

      pending_packets.each do |packet|
        case packet.packet_name
        when 'ADCS'
          # Read 44 Bytes for Position Data
          pos_data = nil
          begin
            pos_data = @position_file.read(44)
            @position_file_bytes_read += 44
          rescue
            # Do Nothing
          end

          if pos_data.nil? or pos_data.length == 0
            # Assume end of file - close and reopen
            @position_file.rewind
            pos_data = @position_file.read(44)
            @position_file_bytes_read = 44
          end

          @pos_packet.buffer = pos_data
          packet.posx = @pos_packet.posx
          packet.posy = @pos_packet.posy
          packet.posz = @pos_packet.posz
          packet.velx = @pos_packet.velx
          packet.vely = @pos_packet.vely
          packet.velz = @pos_packet.velz

          # Read 40 Bytes for Attitude Data
          att_data = nil
          begin
            att_data = @attitude_file.read(40)
            @attitude_file_bytes_read += 40
          rescue
            # Do Nothing
          end

          if att_data.nil? or att_data.length == 0
            @attitude_file.rewind
            att_data = @attitude_file.read(40)
            @attitude_file_bytes_read = 40
          end

          @att_packet.buffer = att_data
          packet.q1 = @att_packet.q1
          packet.q2 = @att_packet.q2
          packet.q3 = @att_packet.q3
          packet.q4 = @att_packet.q4
          packet.biasx = @att_packet.biasx
          packet.biasy = @att_packet.biasy
          packet.biasy = @att_packet.biasz

          packet.star1id = @track_stars[((count_100hz / 100) + 0) % 10]
          packet.star2id = @track_stars[((count_100hz / 100) + 1) % 10]
          packet.star3id = @track_stars[((count_100hz / 100) + 2) % 10]
          packet.star4id = @track_stars[((count_100hz / 100) + 3) % 10]
          packet.star5id = @track_stars[((count_100hz / 100) + 4) % 10]

          packet.posprogress = (@position_file_bytes_read.to_f / @position_file_size.to_f) * 100.0
          packet.attprogress = (@attitude_file_bytes_read.to_f / @attitude_file_size.to_f) * 100.0

          packet.timesec = time.tv_sec - @time_offset
          packet.timeus  = time.tv_usec
          packet.ccsdsseqcnt += 1

        when 'HEALTH_STATUS'
          if @quiet
            @bad_temp2 = false
            cycle_tlm_item(packet, 'temp1', -15.0, 15.0, 5.0)
            cycle_tlm_item(packet, 'temp2', -50.0, 25.0, -1.0)
            cycle_tlm_item(packet, 'temp3', 0.0, 50.0, 2.0)
          else
            cycle_tlm_item(packet, 'temp1', -95.0, 95.0, 5.0)
            if @bad_temp2
              packet.write('temp2', @last_temp2)
              @bad_temp2 = false
            end
            @last_temp2 = cycle_tlm_item(packet, 'temp2', -50.0, 50.0, -1.0)
            if (packet.temp2.abs - 30).abs < 2
              packet.write('temp2', Float::NAN)
              @bad_temp2 = true
            elsif (packet.temp2.abs - 20).abs < 2
              packet.write('temp2', -Float::INFINITY)
              @bad_temp2 = true
            elsif (packet.temp2.abs - 10).abs < 2
              packet.write('temp2', Float::INFINITY)
              @bad_temp2 = true
            end
            cycle_tlm_item(packet, 'temp3', -30.0, 80.0, 2.0)
          end
          cycle_tlm_item(packet, 'temp4', 0.0, 20.0, -0.1)
          cycle_tlm_item(packet, 'bracket[0]', 0, 255, 10)

          packet.timesec = time.tv_sec - @time_offset
          packet.timeus  = time.tv_usec
          packet.ccsdsseqcnt += 1

          ary = []
          10.times do |index|
            ary << index
          end
          packet.ary = ary

          if @quiet
            packet.ground1status = 'CONNECTED'
            packet.ground2status = 'CONNECTED'
          else
            if count_100hz % 1000 == 0
              if packet.ground1status == 'CONNECTED'
                packet.ground1status = 'UNAVAILABLE'
              else
                packet.ground1status = 'CONNECTED'
              end
            end

            if count_100hz % 500 == 0
              if packet.ground2status == 'CONNECTED'
                packet.ground2status = 'UNAVAILABLE'
              else
                packet.ground2status = 'CONNECTED'
              end
            end
          end

        when 'PARAMS'
          packet.timesec = time.tv_sec - @time_offset
          packet.timeus = time.tv_usec
          packet.ccsdsseqcnt += 1
          packet.ip_address = @ip_address

        when 'IMAGE'
          packet.timesec = time.tv_sec - @time_offset
          packet.timeus = time.tv_usec
          packet.ccsdsseqcnt += 1
          if packet.ccsdsseqcnt % 20 == 0
            @cur_image += 1
            @cur_image = 0 if @cur_image == @images.length
          end
          packet.image = @images[@cur_image]
          # Create an Array and then initialize
          # using a sample of all possible hex values (0..15)
          # finally pack it into binary using the Character 'C' specifier
          packet.block = Array.new(1000) { Array(0..15).sample }.pack("C*")

        when 'MECH'
          packet.timesec = time.tv_sec - @time_offset
          packet.timeus = time.tv_usec
          packet.ccsdsseqcnt += 1
          packet.slrpnl1 = @solar_panel_positions[0]
          packet.slrpnl2 = @solar_panel_positions[1]
          packet.slrpnl3 = @solar_panel_positions[2]
          packet.slrpnl4 = @solar_panel_positions[3]
          packet.slrpnl5 = @solar_panel_positions[4]
          packet.current = 0.5

        when 'HIDDEN'
          packet.timesec = time.tv_sec - @time_offset
          packet.timeus = time.tv_usec
          packet.ccsdsseqcnt += 1
        end
      end

      # Every 10s throw an unknown packet at the server just to demo that
      data = Array.new(10) { rand(0..255) }.pack("C*")
      if count_100hz % 1000 == 900
        pending_packets << Packet.new(nil, nil, :BIG_ENDIAN, nil, data)
      end

      pending_packets
    end
  end
end
