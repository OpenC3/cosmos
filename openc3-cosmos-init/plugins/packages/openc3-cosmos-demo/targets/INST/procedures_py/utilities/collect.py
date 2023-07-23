load_utility("<%= target_name %>/procedures/utilities/clear.rb")


def collect(type, duration, call_clear=False):
    # Get the current collects telemetry point
    collects = tlm("<%= target_name %> HEALTH_STATUS COLLECTS")

    # Command the collect
    cmd(f"<%= target_name %> COLLECT with TYPE {type}, DURATION {duration}")

    # Wait for telemetry to update
    wait_check(f"<%= target_name %> HEALTH_STATUS COLLECTS == {collects + 1}", 10)

    if call_clear:
        clear()
