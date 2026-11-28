require "spec_helper"
require "openc3"
require "openc3/packets/packet_config"
require "tempfile"

module OpenC3
  describe LimitsParser do
    describe "integer precision" do
      before(:all) { setup_system() }
      before(:each) { @pc = PacketConfig.new }

      it "preserves all integer limits above float precision" do
        base = 2**54
        limits = [1, 2, 10, 11, 4, 7].map { |offset| base + offset }
        tf = Tempfile.new('unittest')
        tf.puts 'TELEMETRY TGT1 PKT1 BIG_ENDIAN "Packet"'
        tf.puts '  APPEND_ITEM COUNT 64 UINT "Counter"'
        tf.puts "    LIMITS DEFAULT 1 ENABLED #{limits.join(' ')}"
        tf.close
        @pc.process_file(tf.path, "TGT1")
        item = @pc.telemetry["TGT1"]["PKT1"].get_item("COUNT")
        expect(item.limits.values[:DEFAULT]).to eq(limits)
        tf.unlink
      end

      it "reports red high for uint64 above the configured red high" do
        value = 2**64 - 1
        tf = Tempfile.new('unittest')
        tf.puts 'TELEMETRY TGT1 PKT1 BIG_ENDIAN "Packet"'
        tf.puts '  APPEND_ITEM COUNT 64 UINT "Counter"'
        tf.puts "    LIMITS DEFAULT 1 ENABLED 0 1 #{value - 2} #{value - 1}"
        tf.close
        @pc.process_file(tf.path, "TGT1")
        packet = @pc.telemetry["TGT1"]["PKT1"]
        packet.buffer = [value].pack('Q>')
        packet.check_limits
        expect(packet.read("COUNT")).to eq(value)
        expect(packet.get_item("COUNT").limits.state).to eq(:RED_HIGH)
        expect(packet.out_of_limits).to eq([["TGT1", "PKT1", "COUNT", :RED_HIGH]])
        tf.unlink
      end

      it "reports red low for int64 at the configured red low" do
        value = -(2**54) - 7
        tf = Tempfile.new('unittest')
        tf.puts 'TELEMETRY TGT1 PKT1 BIG_ENDIAN "Packet"'
        tf.puts '  APPEND_ITEM COUNT 64 INT "Counter"'
        tf.puts "    LIMITS DEFAULT 1 ENABLED #{value} #{value + 1} 0 1"
        tf.close
        @pc.process_file(tf.path, "TGT1")
        packet = @pc.telemetry["TGT1"]["PKT1"]
        packet.buffer = [value].pack('q>')
        packet.check_limits
        expect(packet.read("COUNT")).to eq(value)
        expect(packet.get_item("COUNT").limits.state).to eq(:RED_LOW)
        expect(packet.out_of_limits).to eq([["TGT1", "PKT1", "COUNT", :RED_LOW]])
        tf.unlink
      end

    end
  end
end
