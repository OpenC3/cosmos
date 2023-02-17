require 'openc3/interfaces/interface'
require 'openc3/interfaces/protocols/protocol'
require 'openc3/api/api'

module OpenC3
  class MyRejectProtocol < Protocol
    include Api

    def write_packet(packet)
      if packet.packet_name == 'START'
        temp = tlm("INST HEALTH_STATUS TEMP1")
        if temp > 50
          raise WriteRejectError, "TEMP1 too high for command"
        elsif temp < -50
          raise WriteRejectError, "TEMP1 too low for command"
        end
      end
      return packet
    end
  end
end
