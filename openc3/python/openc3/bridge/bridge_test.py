from openc3.bridge.bridge import Bridge

def run_bridge(filename):
    variables = {}
    bridge = Bridge(filename, variables)
    while True:
        try:
            sleep(1)
        except Exception as e:
            exit(0)

run_bridge('bridge.txt')