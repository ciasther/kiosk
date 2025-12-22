
sudo nano /etc/lightdm/lightdm.conf.d/50-autologin.conf

[Seat:*]
autologin-user=kiosk
autologin-user-timeout=0
user-session=openbox

[Seat:*]
#autologin-user=kiosk
autologin-user-timeout=0
user-session=ubuntu

sudo dpkg-reconfigure gdm3
sudo dpkg-reconfigure lightdm