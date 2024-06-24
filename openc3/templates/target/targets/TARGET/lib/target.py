# This class can be used in your scripts like so:
#   load_utility '<%= target_class.upcase %>/lib/<%= target_lib_filename %>'
#   <%= target_object %> = <%= target_class %>()
#   <%= target_object %>.utility()
# For more information see the OpenC3 scripting guide

from openc3.script import *

class <%= target_class %>:
    def utility(self):
        pass
