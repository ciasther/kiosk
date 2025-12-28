1.

```
sudo libinput list-devices | grep -i "eGalax" -A 5
```

2.

```
sudo nano /etc/udev/rules.d/99-egalax-calibration.rules
```
```
ACTION=="add|change", KERNEL=="event[0-9]*", ENV{ID_INPUT_TOUCHSCREEN}=="1", ATTRS{name}=="*eGalax*", ENV{LIBINPUT_CALIBRATION_MATRIX}="0 1 0 -1 0 1"
```

3. 
```
sudo cp ~/.config/monitors.xml /etc/xdg/monitors.xml
```

4.
```
sudo reboot
``` 