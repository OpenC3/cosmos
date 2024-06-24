---
title: Raspberry Pi
---

### COSMOS Running on Raspberry Pi 4

The Raspberry Pi 4 is a low-cost powerful ARM-based minicomputer that runs linux. And because it runs modern linux, it can also run COSMOS! These directions will get you up and running.

What you'll need:

- Raspberry Pi 4 board (tested with 8GB RAM)
- A Pi Case but Optional
- Raspbeerry Pi Power Supply
- 32GB or Larger SD Card - Also faster the better
- A Laptop with a way to write SD Cards

Let's get started!

1. Setup 64-bit Raspian OS Lite on the SD Card

   Make sure you have the Raspberry Pi Imager app from: https://www.raspberrypi.com/software/

   1. Insert the SD Card into your computer (Note this process will erase all data on the SD card!)
   1. Open the Raspberry Pi Imager App
   1. Click the "Choose Device" Button
   1. Pick Your Raspberry Pi Model
   1. Click the "Choose OS" Button
   1. Select "Raspberry Pi OS (other)"
   1. Select "Raspberry Pi OS Lite (64-bit)"
   1. Click the "Choose Storage" Button
   1. Select Your SD Card
   1. Click Edit Settings
   1. If prompted if you would like to prefill the Wifi information, select OK
   1. Set the hostname to: cosmos.local
   1. Set the username and password. The default username is your username, you should also set a password to make the system secure
   1. Fill in your Wifi info, and set the country appropriately (ie. US)
   1. Set the correct time zone
   1. Goto the Services Tab and Enable SSH
   1. You can either use Password auth, or public-key only if your computer is already setup for passwordless SSH
   1. Goto the Options tab and make sure "Enable Telemetry" is not checked
   1. Click "Save" when everything is filled out
   1. Click "Yes" to apply OS Customization Settings, Yes to Are You Sure, and Wait for it to complete

1. Make sure the Raspberry Pi is NOT powered on

1. Remove the SD Card from your computer and insert into the Raspberry Pi

1. Apply power to the Raspberry Pi and wait approximately 1 minute for it to boot

1. SSH to your raspberry Pi

   1. Open a terminal window and use ssh to connect to your Pi

      1. On Mac / Linux: ssh yourusername@cosmos.local
      1. On Windows, use Putty to connect. You will probably have to install Bonjour for Windows for .local addresses to work as well.

1. From SSH, Enter the following commands

```bash
   sudo sysctl -w vm.max_map_count=262144
   sudo sysctl -w vm.overcommit_memory=1
   sudo apt update
   sudo apt upgrade
   sudo apt install git -y
   curl -fsSL https://get.docker.com -o get-docker.sh
   sudo sh get-docker.sh
   sudo usermod -aG docker $USER
   newgrp docker
   git clone https://github.com/OpenC3/cosmos-project.git cosmos
   cd cosmos
   # Edit compose.yaml and remove 127.0.0.1: from the ports section of the openc3-traefik service
   ./openc3.sh run
```

1. After about 2 minutes, open a web browser on your computer, and goto: http://cosmos.local:2900

1. Congratulations! You now have COSMOS running on a Raspberry Pi!
