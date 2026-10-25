# Python code shared across this plugin lives in this package. COSMOS puts
# every installed plugin's lib/ on sys.path, so a module placed directly in
# lib/ can collide with another plugin's module of the same name. Keeping it
# under this uniquely named package avoids that. See README.md.
