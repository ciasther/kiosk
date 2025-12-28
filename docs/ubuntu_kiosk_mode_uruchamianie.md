Ubuntu Kiosk Mode - Szybki Przewodnik

Co trzeba zrobić aby webapp działał fullscreen bez pulpitu

1. INSTALACJA PAKIETÓW
```bash
sudo apt-get update
sudo apt-get install -y openbox firefox unclutter x11-xserver-utils
```

2. KONFIGURACJA OPENBOX AUTOSTART
```bash
mkdir -p ~/.config/openbox
nano ~/.config/openbox/autostart
```

Zawartość:
```bash
xset s off
xset s noblank
xset -dpms
unclutter -idle 0.1 &
firefox --kiosk http://localhost:9102 &
```

```bash
chmod +x ~/.config/openbox/autostart
```

3. XINITRC
```bash
echo "exec openbox-session" > ~/.xinitrc
chmod +x ~/.xinitrc
```

4. BASH PROFILE (autostart X)
```bash
nano ~/.bash_profile
```

Zawartość:
```bash
if [ -z "$DISPLAY" ] && [ "$XDG_VTNR" -eq 1 ]; then
  exec startx
fi
```

5. WYŁĄCZ GDM I USTAW MULTI-USER TARGET
*TO NAJWAŻNIEJSZE! Bez tego będzie pulpit GNOME!*

```bash
sudo systemctl disable gdm.service
sudo systemctl set-default multi-user.target
```

6. AUTOLOGIN NA TTY1
```bash
sudo mkdir -p /etc/systemd/system/getty@tty1.service.d/
sudo nano /etc/systemd/system/getty@tty1.service.d/autologin.conf
```

Zawartość (zamień USERNAME na swojego):
```ini
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin USERNAME --noclear %I $TERM
```

7. RELOAD I RESTART
```bash
sudo systemctl daemon-reload
sudo systemctl enable getty@tty1.service
sudo reboot
```

WERYFIKACJA PO RESTARCIE

```bash
Sprawdź procesy
ps aux | grep firefox

Sprawdź sesję
who

Sprawdź target (powinno być multi-user.target)
systemctl get-default
```

NAJCZĘSTSZY BŁĄD

*Problem*: Po restarcie pokazuje się pulpit Ubuntu/GNOME

*Przyczyna*: GDM nadal aktywny lub graphical.target

*Rozwiązanie*:
```bash
sudo systemctl disable gdm.service
sudo systemctl disable gdm3.service
sudo systemctl set-default multi-user.target
sudo reboot
```

AWARYJNY DOSTĘP

- Ctrl+Alt+F2 (przejście do tty2)
- Zaloguj się ręcznie
- Zatrzymaj X: `sudo pkill -9 X`

KOLEJNOŚĆ (WAŻNE!)

1.  Pakiety (openbox, firefox, unclutter)
2.  ~/.config/openbox/autostart
3.  ~/.xinitrc
4.  ~/.bash_profile
5.  *DISABLE GDM* ← BEZ TEGO NIE DZIAŁA!
6.  *SET multi-user.target* ← BEZ TEGO NIE DZIAŁA!
7.  Autologin getty@tty1
8.  Reboot

OPCJONALNIE: Chromium zamiast Firefox

```bash
W ~/.config/openbox/autostart zamień:
firefox --kiosk http://localhost:9102 &

Na:
chromium-browser --kiosk --noerrdialogs --disable-infobars http://localhost:9102 &
```
