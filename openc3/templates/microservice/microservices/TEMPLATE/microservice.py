import time
from openc3.microservices.microservice import Microservice
from openc3.utilities.sleeper import Sleeper
from openc3.api import *


class <%= microservice_class %>(Microservice):
    def __init__(self, name):
        super().__init__(name)
        for option in self.config['options']:
            # Update with your own OPTION handling
            match option[0].upper():
                case 'PERIOD':
                    self.period = int(option[1])
                case _:
                    self.logger.error(
                        "Unknown option passed to microservice #{@name}: #{option}"
                    )

        if not self.period:
            self.period = 60  # 1 minutes
        self.sleeper = Sleeper()

    def run(self):
        while True:
            start_time = time.time()
            if self.cancel_thread:
                break

            # Do your microservice work here
            self.logger.info("Template Microservice ran")
            # cmd("INST ABORT")

            # The self.state variable is set to 'RUNNING' by the microservice base class
            # The self.state is reflected to the user in the MICROSERVICES tab so you can
            # convey long running actions by changing it, e.g. self.state = 'CALCULATING ...'

            run_time = time.time() - start_time
            delta = self.period - run_time
            if delta > 0:
                # Delay till the next period
                if self.sleeper.sleep(
                    delta
                ):  # returns true and breaks loop on shutdown
                    break
            self.count += 1

    def shutdown(self):
        self.sleeper.cancel()  # Breaks out of run()
        super().shutdown()


if __name__ == "__main__":
    <%= microservice_class %>.run()
