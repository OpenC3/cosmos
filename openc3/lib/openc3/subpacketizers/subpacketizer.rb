class Subpacketizer
  attr_reader :args

  def initialize(packet=nil)
    @packet = packet
    @args = []
  end

  # Subclass and implement this method to break packet into array of subpackets
  # Subpackets should be fully identified and defined
  def call(packet)
    return [packet]
  end

  def as_json(*a)
    { 'class' => self.class.name, 'args' => @args.as_json(*a) }
  end
end