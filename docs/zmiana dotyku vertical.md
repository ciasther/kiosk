1. ustawienie X11 zamiast wayland
```bash
sudo nano /etc/gdm3/custom.conf
```

odhashować WaylandEnable=false
ctrl+o > enter > ctrl+x



2. ustawienie dotyku z horizontal na vertical
```bash
sudo nano /etc/X11/xorg.conf.d/99-calibration.conf
```
przekopiuj to do srodka
```nano
Section "InputClass"
  Identifier "eGalax Touchscreen Calibration"
  MatchProduct "eGalax"
  Driver "evdev"
  Option "TransformationMatrix" "0 1 0 -1 0 1 0 0 1"
EndSection
```
ctrl+o > enter > ctrl+x

3. skopiowanie ustawien dla ekranu logowania:
```bash
sudo cp ~/.config/monitors.xml /etc/xdg/monitors.xml
```

4.. restart
```bash
sudo reboot
```




