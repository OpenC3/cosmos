import math
from openc3.processors.processor import Processor

# Custom processor class
# See https://docs.openc3.com/docs/configuration/processors
class <%= processor_class %>(Processor):
    def __init__(self, item_name, num_samples, value_type='CONVERTED'):
        super().__init__(value_type)
        self.item_name = item_name.upper()
        self.num_samples = int(num_samples)
        self.reset()

    def call(self, value, packet, buffer):
        value = packet.read(self.item_name, self.value_type, buffer)
        # Don't process NaN or Infinite values
        if math.isnan(value) or math.isinf(value):
            return

        self.samples.append(value)
        if len(self.samples) > self.num_samples:
            self.samples = self.samples[-self.num_samples :]

        # Calculate something based on the collected samples
        # For example, calculate the rate of change:
        if len(self.samples) > 1:
            self.results['RATE_OF_CHANGE'] = (self.samples[-1] - self.samples[0]) / (len(self.samples) - 1)
        else:
            self.results['RATE_OF_CHANGE'] = None

    def reset(self):
        self.samples = []
        self.results['RATE_OF_CHANGE'] = None
