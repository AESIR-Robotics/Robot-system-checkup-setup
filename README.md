Tested on Ubuntu 22.04.5 LTS

This code handles automatic github repository updates for deployment upon system boot.
You are able to put as much repositories under the directory Repos as you like.
When listing the repo name and branch on /etc/robot_repos.conf it will be automatically taken care of.

This code also handles devices detected by udev.
It monitors constantly when the device gets connected and disconnected.
You are able to run arbitrary code upon this device, allowing you to automaticalle flash the device if it is a microcontroller.
firmware/flash.sh will be run (we recommend you to change this file)

All movements are logged under the log directory 
(Including device connection, disconnection and github updates and deployment code)

You must update:
reminders/robot_repos.conf # To track your repositories and branches
70-monitor.rules # To track your devices