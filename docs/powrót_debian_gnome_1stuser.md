powrót do defaultowego admin usera z defaultowym pulpitem debian13

```bash
sudo nano /etc/lightdm/lightdm.conf
```
zamienic usera oraz sesje z openbox na gnome (lub inne)
```
[Seat:*]
autologin-user=admin1
autologin-user-timeout=0
autologin-session=gnome
user-session=gnome
greeter-session=lightdm-gtk-greeter
```

```bash
sudo reboot
```
