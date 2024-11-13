from time import sleep
import paho.mqtt.client as mqtt

def on_subscribe(client, userdata, mid, reason_code_list, properties):
    print(f"mid: {mid} reason_code_list: {reason_code_list} properties: {properties}")
    # Since we subscribed only for a single channel, reason_code_list contains
    # a single entry
    if reason_code_list[0].is_failure:
        print(f"Broker rejected you subscription: {reason_code_list[0]}")
    else:
        print(f"Broker granted the following QoS: {reason_code_list[0].value}")

def on_unsubscribe(client, userdata, mid, reason_code_list, properties):
    # Be careful, the reason_code_list is only present in MQTTv5.
    # In MQTTv3 it will always be empty
    if len(reason_code_list) == 0 or not reason_code_list[0].is_failure:
        print("unsubscribe succeeded (if SUBACK is received in MQTTv3 it success)")
    else:
        print(f"Broker replied with failure: {reason_code_list[0]}")
    client.disconnect()

def on_message(client, userdata, message):
    # userdata is the structure we choose to provide, here it's a list()
    print(f"Received message '{message.payload}' on topic '{message.topic}' with QoS {message.qos}")
    userdata.append(message.payload)
    # We only want to process 10 messages
    if len(userdata) >= 10:
        client.unsubscribe("$SYS/#")

def on_connect(client, userdata, flags, reason_code, properties):
    if reason_code.is_failure:
        print(f"Failed to connect: {reason_code}. loop_forever() will retry connection")
    else:
        # we should always subscribe from on_connect callback to be sure
        # our subscribed is persisted across reconnections.
        print("subscribe to test")
        client.subscribe("24V_Main")
        # client.subscribe("test")
        # client.subscribe([("$SYS/#", 0)], ("test", 0))

mqttc = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
mqttc.on_connect = on_connect
mqttc.on_message = on_message
mqttc.on_subscribe = on_subscribe
mqttc.on_unsubscribe = on_unsubscribe

# mqttc.username_pw_set('rw', 'readwrite')
mqttc.tls_set(ca_certs = './mosquitto.org.crt')#, certfile = './client.crt', keyfile = './client.key')
mqttc.tls_insecure_set(True)
# mqttc.tls_set(ca_certs = './mosquitto.org.crt')
mqttc.user_data_set([])
mqttc.loop_start()
mqttc.connect("test.mosquitto.org", 8884)
sleep(1)
mqttc.publish("test", "Hello World")
sleep(1)
print(f"Received the following message: {mqttc.user_data_get()}")