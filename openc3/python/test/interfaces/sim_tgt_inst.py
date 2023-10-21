from openc3.utilities.simulated_target import SimulatedTarget
from openc3.packets.packet import Packet


class SimTgtInst(SimulatedTarget):
    packet = None

    def __init__(self, target):
        super().__init__(target)

    def set_rates(self):
        pass

    def write(self, packet):
        SimTgtInst.packet = packet

    def read(self, count, time):
        pkts = []
        pkts.append(Packet("INST", "ADCS"))
        pkts.append(Packet("INST", "HEALTH_STATUS"))
        return pkts
