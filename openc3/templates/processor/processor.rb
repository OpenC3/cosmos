# encoding: ascii-8bit
require 'openc3/processors/processor'

module OpenC3
  # Custom processor class
  # See https://docs.openc3.com/docs/configuration/processors
  class <%= processor_class %> < Processor
    def initialize(item_name, num_samples, value_type = :CONVERTED)
      super(value_type)
      @item_name = item_name.to_s.upcase
      @num_samples = Integer(num_samples)
      reset()
    end

    # This is where the processor does its work.
    # All processor results should be stored in the @results hash.
    # Results are accessed via a ProcessorConversion
    def call(packet, buffer)
      value = packet.read(@item_name, @value_type, buffer)
      # Don't process NaN or Infinite values
      return if value.to_f.nan? || value.to_f.infinite?

      @samples << value
      @samples = @samples[-@num_samples..-1] if @samples.length > @num_samples
      # Calculate something based on the collected samples
      # For example, calculate the rate of change:
      @results[:RATE_OF_CHANGE] = (@samples.last - @samples.first) / (@samples.length - 1) if @samples.length > 1
    end

    # Reset any state
    def reset
      @samples = []
      @results[:RATE_OF_CHANGE] = nil
    end
  end
end
