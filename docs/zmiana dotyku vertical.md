1\.
sudo nano /etc/gdm3/custom.conf

odhashować WaylandEnable=false

2.
sudo nano /etc/X11/xorg.conf.d/99-calibration.conf



Section "InputClass"

&nbsp;	Identifier "eGalax Touchscreen Calibration"

&nbsp;	MatchProduct "eGalax"

&nbsp;	MatchDevicePath "/dev/input/event4"

&nbsp;	Driver "evdev"

&nbsp;	Option "TransformationMatrix" "0 1 0 -1 0 1 0 0 1"

EndSection


3. 
sudo reboot



