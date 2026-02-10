## Najpierw sprawdź tryb (Wayland/X11)

```bash
echo $XDG_SESSION_TYPE
```
Pokaże `wayland` albo `x11`.

***

## Wayland (GNOME)

```bash
gnome-control-center display
```
Otwórz „Orientacja” i ustaw pionowo.

```bash
sudo tee /etc/udev/rules.d/99-touch-rotate.rules >/dev/null <<'EOF'
ACTION=="add|change", KERNEL=="event[0-9]*", ENV{ID_INPUT_TOUCHSCREEN}=="1", ATTRS{name}=="*eGalax*", ENV{LIBINPUT_CALIBRATION_MATRIX}="0 1 0 -1 0 1"
EOF
```
Ustawia obrót dotyku (dla eGalax) w Waylandzie.

```bash
sudo udevadm control --reload-rules
```
Wczytuje nowe reguły dotyku.

```bash
sudo udevadm trigger
```
Stosuje reguły bez restartu.

```bash
sudo reboot
```
Restart (najpewniejsze).

Macierze (gdy dotyk jest „w złą stronę” — podmień liczby w pliku reguły):  
- Normalnie: `1 0 0 0 1 0`
- 90° w prawo: `0 -1 1 1 0 0`
- 180°: `-1 0 1 0 -1 1`
- 270° w prawo: `0 1 0 -1 0 1`

***

## X11 (GNOME on Xorg)

```bash
gnome-control-center display
```
Otwórz „Orientacja” i ustaw pionowo.

```bash
xinput list
```
Znajdź nazwę urządzenia dotykowego (np. „eGalax…”).

```bash
xinput set-prop 'TU_WKLEJ_NAZWE_DOTYKU' 'Coordinate Transformation Matrix' 0 1 0 -1 0 1 0 0 1
```
Ustawia obrót dotyku (działa do wylogowania).

```bash
tee ~/.xprofile >/dev/null <<'EOF'
xinput set-prop 'TU_WKLEJ_NAZWE_DOTYKU' 'Coordinate Transformation Matrix' 0 1 0 -1 0 1 0 0 1
EOF
```
Ustawia to samo automatycznie po zalogowaniu.

```bash
chmod +x ~/.xprofile
```
Włącza uruchamianie pliku przy starcie sesji.

Macierze X11 (podmień 9 liczb w komendzie `xinput`):  
- Normalnie: `1 0 0 0 1 0 0 0 1`
- 90° w prawo: `0 -1 1 1 0 0 0 0 1`
- 180°: `-1 0 1 0 -1 1 0 0 1`
- 270° w prawo: `0 1 0 -1 0 1 0 0 1`