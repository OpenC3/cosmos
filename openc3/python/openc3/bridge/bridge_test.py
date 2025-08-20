from openc3.bridge.bridge import Bridge

def run_bridge(filename):
    variables = {}
    bridge = Bridge(filename, variables)
    bridge.wait_forever()

run_bridge('bridge.txt')