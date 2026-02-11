Tested on Ubuntu 22.04.5 LTS

This code handles automatic github repository updates upon system boot.
You are able to put as much repositories under the directory Repos as you like.
When listing the repo name and branch on /etc/robot_repos.conf it will be automatically taken care of.

This code also handles devices detected by udev.
It monitors constantly when the device gets connected and disconnected.
You are able to run arbitrary code upon this device, allowing you to automaticalle flash the device if it is a microcontroller.

All movements are logged under the log directory 
(Including device connection, disconnection and github updates)

Further updates to this code will be to better handle the device system arbitrary code handling because it is still a little raw and as of right now just intended for teensy 4.0, arduino and esp32.
It will have a service to handle automatic compilation and/or care of repositories as per user needs.