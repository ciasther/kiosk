# Troubleshooting Guide - Gastro Kiosk Pro

**Wersja**: 2.0.0  
**Data**: 2025-12-22

Ten dokument zawiera rozwiązania najczęstszych problemów z kioskami.

---

## SZYBKA DIAGNOZA

### Drzewo decyzyjne

```
Start → Czy urządzenie się włącza?
  ├─ NIE → Problem z zasilaniem (patrz: HARDWARE)
  └─ TAK → Czy widzisz ekran logowania/pulpit?
       ├─ NIE (czarny ekran) → Problem z Display Manager (patrz: DISPLAY)
       └─ TAK → Czy aplikacja się uruchomiła?
            ├─ NIE → Problem z systemd service (patrz: SERVICE)
            └─ TAK → Czy aplikacja się łączy?
                 ├─ NIE → Problem z VPN/Network (patrz: NETWORK)
                 └─ TAK → Problem funkcjonalny (patrz: FUNCTIONAL)
```

---

## KATEGORIA 1: HARDWARE

### Problem: Urządzenie się nie włącza

**Objawy**:
- Czarny ekran
- Brak LED zasilania
- Żadnej reakcji na przyciski

**Rozwiązanie**:
```bash
1. Sprawdź zasilanie
   - Czy wtyczka podłączona?
   - Czy gniazdko działa? (test innym urządzeniem)
   - Czy LED zasilania świeci?

2. Sprawdź przyciski
   - Naciśnij i przytrzymaj przycisk power 5s
   - Niektóre urządzenia mają przełącznik na tylnej ścianie

3. Hard reset
   - Odłącz zasilanie na 30s
   - Podłącz ponownie
   - Uruchom
```

---

### Problem: Ekran dotykowy nie reaguje

**Objawy**:
- Aplikacja widoczna ale touch nie działa
- Musisz używać myszy

**Rozwiązanie**:
```bash
# SSH do urządzenia
ssh kiosk@<IP>

# Sprawdź czy system widzi touchscreen
xinput list

# Powinno pokazać: "touchscreen" lub "capacitive touch"
# Jeśli nie ma, sprawdź:
lsusb  # Czy urządzenie USB widoczne

# Test touchscreen
xinput test <DEVICE_ID>
# Dotknij ekran - powinny pojawić się eventy

# Jeśli nie działa, restart X11
sudo systemctl restart lightdm
```

**Kalibracja touchscreen**:
```bash
# Zainstaluj narzędzie
sudo apt install xinput-calibrator

# Uruchom kalibrację
DISPLAY=:0 xinput_calibrator

# Postępuj zgodnie z instrukcjami na ekranie
```

---

### Problem: Drukarka nie drukuje

**Objawy**:
- Zamówienie złożone ale brak wydruku
- Błąd "Nie można wydrukować biletu"
- Błąd "Resource busy" w logach
- Drukarka świeci czerwonym LED

**Najczęstsze przyczyny (v3.0.10)**:

#### 1. CUPS blokuje drukarkę (Resource busy) 🔴 CRITICAL

**Symptom**: `[Errno 16] Resource busy` w logach

```bash
# Wyłącz CUPS permanentnie
sudo systemctl stop cups cups.socket cups.path cups-browsed
sudo systemctl disable cups cups.socket cups.path cups-browsed
sudo systemctl mask cups  # Zapobiega auto-startowi!

# Sprawdź
systemctl status cups  # Powinno być: masked

# Restart printer-service
sudo systemctl restart gastro-printer.service
```

#### 2. Moduł usblp konfliktuje z ESC/POS

```bash
# Blacklist usblp
sudo bash -c 'cat > /etc/modprobe.d/blacklist-usblp.conf <<EOF
blacklist usblp
EOF'

# Wyładuj
sudo rmmod usblp 2>/dev/null

# Sprawdź (powinien być pusty)
lsmod | grep usblp
```

#### 3. Brak modułów Python

**Symptom**: `ModuleNotFoundError: No module named 'escpos'`

```bash
# Ubuntu 24.04
pip3 install --break-system-packages python-escpos pillow

# Ubuntu 22.04
pip3 install python-escpos pillow
```

#### 4. Brak uprawnień

**Symptom**: `[Errno 13] Access denied`

```bash
sudo usermod -a -G lp,dialout $USER
# Wyloguj i zaloguj ponownie
```

#### 5. Endpoint mismatch

**Symptom**: Backend logs: `Request failed with status code 404`

Backend i printer-service muszą używać `/print` (nie `/print/ticket`)

#### 6. Standardowa diagnoza

```bash
# 1. Sprawdź drukarkę USB
lsusb | grep -i hwasung
# Powinno: 0006:000b hwasung HWASUNG USB Printer I/F

# 2. Test drukowania
curl -X POST http://localhost:8083/test

# 3. Sprawdź service
systemctl status gastro-printer.service

# 4. Logi
journalctl -u gastro-printer.service -n 50
```

**Więcej szczegółów**: Zobacz `AGENTS.md` sekcja "🖨️ PRINTER INTEGRATION"
```

---

### Problem: Terminal płatniczy nie odpowiada

**Objawy**:
- Płatność CARD niedostępna
- Terminal pokazuje błąd
- "Płatność nie powiodła się"

**Rozwiązanie**:
```bash
# 1. Sprawdź zasilanie terminala
# Terminal musi być WŁĄCZONY (zielony ekran)

# 2. Sprawdź kabel Ethernet
# Czy świecą LED na porcie?

# 3. Sprawdź IP terminala
# Na terminalu: Menu → Zarządzanie → Wizytówka
# Zapisz IP (np. 10.42.0.75)

# 4. Test ping
ping 10.42.0.75

# 5. Sprawdź usługę
systemctl status gastro-terminal.service

# 6. Restart usługi
sudo systemctl restart gastro-terminal.service

# 7. Sprawdź rejestrację w device-manager
curl http://100.64.0.7:8090/devices/$(hostname)
# Powinno zwrócić: "paymentTerminal": true
```

---

## KATEGORIA 2: DISPLAY MANAGER

### Problem: Czarny ekran po starcie (brak GUI)

**Objawy**:
- System bootuje ale widzisz tylko czarny ekran
- LUB widzisz tylko terminal tekstowy (TTY)
- Brak środowiska graficznego

**Rozwiązanie 1: Sprawdź Display Manager**:
```bash
# Przełącz się na TTY (Ctrl+Alt+F2)
# Zaloguj: kiosk / gastro2024

# Sprawdź status LightDM
sudo systemctl status lightdm

# Jeśli "inactive" - uruchom
sudo systemctl start lightdm

# Jeśli "failed" - sprawdź logi
sudo journalctl -u lightdm -n 50

# Jeśli "masked" - odmaskuj
sudo systemctl unmask lightdm
sudo systemctl enable lightdm
sudo systemctl start lightdm
```

**Rozwiązanie 2: Sprawdź X11**:
```bash
# Czy X server działa?
ps aux | grep Xorg

# Test X11
DISPLAY=:0 xset q
# Jeśli błąd "unable to open display" - X11 nie działa

# Sprawdź logi X11
cat /var/log/Xorg.0.log | grep EE
```

**Rozwiązanie 3: Reinstalacja Display Manager**:
```bash
sudo apt install --reinstall lightdm
sudo dpkg-reconfigure lightdm
sudo reboot
```

---

### Problem: Aplikacja nie uruchamia się automatycznie

**Objawy**:
- Widzisz pulpit Openbox
- Chromium się nie otwiera
- Musisz ręcznie uruchomić aplikację

**Rozwiązanie**:
```bash
# 1. Sprawdź status usługi
systemctl status gastro-kiosk.service

# Jeśli "inactive":
sudo systemctl start gastro-kiosk.service

# Jeśli "failed" - sprawdź błąd
journalctl -u gastro-kiosk.service -n 20

# 2. Sprawdź czy usługa jest włączona
systemctl is-enabled gastro-kiosk.service
# Powinno zwrócić: "enabled"

# Jeśli "disabled":
sudo systemctl enable gastro-kiosk.service

# 3. Sprawdź skrypt startowy
ls -l /usr/local/bin/gastro-kiosk-start.sh
# Powinno być: -rwxr-xr-x (executable)

# Jeśli nie jest executable:
sudo chmod +x /usr/local/bin/gastro-kiosk-start.sh

# 4. Test ręcznego uruchomienia
sudo -u kiosk DISPLAY=:0 /usr/local/bin/gastro-kiosk-start.sh
# Sprawdź co się dzieje
```

---

### Problem: Wiele instancji Chromium

**Objawy**:
- 2 lub więcej okien Chromium
- Aplikacja otwiera się kilka razy
- Powolne działanie systemu

**Rozwiązanie**:
```bash
# 1. Sprawdź ile procesów
ps aux | grep chromium | grep -v grep | wc -l
# Powinno być: 1 (może być kilka wątków jednego procesu)

# 2. Zabij wszystkie chromium
pkill -f chromium
sleep 3

# 3. Wyłącz konfliktujące autostarty
# XDG autostart
mv ~/.config/autostart/chromium.desktop \
   ~/.config/autostart/chromium.desktop.disabled 2>/dev/null

# Openbox autostart - sprawdź i usuń chromium
nano ~/.config/openbox/autostart
# Usuń wszystkie linie z "chromium"
# Zostaw tylko: xset, unclutter

# 4. Wyłącz stare usługi
for svc in kiosk-frontend bakery-kiosk-browser; do
  sudo systemctl disable $svc.service 2>/dev/null
  sudo systemctl stop $svc.service 2>/dev/null
done

# 5. Restart usługi
sudo systemctl restart gastro-kiosk.service

# 6. Sprawdź ponownie
ps aux | grep chromium | grep -v grep
```

---

## KATEGORIA 3: NETWORK & VPN

### Problem: VPN się nie łączy

**Objawy**:
- `tailscale status` pokazuje "Stopped" lub brak połączenia
- Nie widać serwera 100.64.0.7
- Aplikacja pokazuje "Cannot connect to server"

**Rozwiązanie 1: Restart Tailscale**:
```bash
# Sprawdź status
sudo tailscale status

# Restart usługi
sudo systemctl restart tailscaled
sleep 5

# Spróbuj połączyć ponownie
sudo tailscale up
```

**Rozwiązanie 2: Ponowne połączenie z authkey**:
```bash
# Wyloguj
sudo tailscale down
sudo tailscale logout

# Wygeneruj NOWY authkey na serwerze:
# ssh kiosk-server@192.168.31.139
# headscale preauthkeys create --expiration 24h

# Połącz z nowym kluczem
sudo tailscale up \
  --login-server="https://headscale.your-domain.com" \
  --authkey="NOWY_AUTHKEY" \
  --hostname="$(hostname)" \
  --accept-routes

# Sprawdź
sudo tailscale status | grep 100.64.0.7
```

**Rozwiązanie 3: Sprawdź connectivity**:
```bash
# Czy internet działa?
ping -c 3 8.8.8.8

# Czy DNS działa?
nslookup google.com

# Czy headscale server dostępny?
curl -I https://headscale.your-domain.com
```

---

### Problem: Aplikacja pokazuje "Cannot connect to server"

**Objawy**:
- Chromium otwarty
- Biały ekran z błędem połączenia
- LUB nieskończone ładowanie

**Rozwiązanie**:
```bash
# Test 1: Czy VPN działa?
tailscale status | grep 100.64.0.7
# Musi pokazać: "online"

# Test 2: Czy backend odpowiada?
curl -k https://100.64.0.7:3000/api/health
# Powinno zwrócić: {"status":"ok"}

# Test 3: Czy frontend dostępny?
curl -k -I https://100.64.0.7:3001
# Powinno zwrócić: HTTP/1.1 200 OK

# Jeśli Test 1 failed → Problem z VPN (patrz wyżej)
# Jeśli Test 2/3 failed → Problem po stronie SERWERA:
```

**Problem po stronie serwera** (SSH do kiosk-server):
```bash
ssh kiosk-server@192.168.31.139

# Sprawdź kontenery
docker ps
# Wszystkie 5 powinny być UP:
# - gastro_nginx
# - gastro_backend
# - gastro_postgres
# - gastro_redis
# - gastro_device_manager

# Jeśli któryś DOWN - restart
docker compose restart backend
docker compose restart nginx

# Sprawdź logi
docker logs gastro_backend --tail 50
docker logs gastro_nginx --tail 50
```

---

## KATEGORIA 4: SERVICE ISSUES

### Problem: gastro-kiosk.service failed

**Objawy**:
- `systemctl status gastro-kiosk.service` pokazuje "failed"
- Aplikacja się nie uruchamia

**Rozwiązanie**:
```bash
# 1. Sprawdź dokładny błąd
journalctl -u gastro-kiosk.service -n 50

# Typowe błędy:

# BŁĄD: "X11 server timeout"
# Rozwiązanie: Display manager nie działa
sudo systemctl restart lightdm
sudo systemctl restart gastro-kiosk.service

# BŁĄD: "VPN connection timeout"
# Rozwiązanie: VPN nie połączony
sudo tailscale up
sudo systemctl restart gastro-kiosk.service

# BŁĄD: "Cannot reach server"
# Rozwiązanie: Backend nie odpowiada (sprawdź serwer)

# BŁĄD: "Permission denied"
# Rozwiązanie: Brak uprawnień do XAUTHORITY
sudo chown kiosk:kiosk /home/kiosk/.Xauthority
sudo systemctl restart gastro-kiosk.service

# 2. Jeśli błąd niejasny - uruchom ręcznie
sudo -u kiosk \
  DISPLAY=:0 \
  XAUTHORITY=/home/kiosk/.Xauthority \
  /usr/local/bin/gastro-kiosk-start.sh
# Obserwuj co się dzieje
```

---

### Problem: Chromium crash loop

**Objawy**:
- Chromium się uruchamia i zamyka w kółko
- Migający ekran
- Logi pokazują ciągłe restarty

**Rozwiązanie**:
```bash
# 1. Zatrzymaj usługę
sudo systemctl stop gastro-kiosk.service

# 2. Wyczyść profil Chromium
rm -rf /tmp/chromium-kiosk-*
rm -rf /home/kiosk/.config/chromium

# 3. Sprawdź czy inny chromium nie działa
pkill -9 chromium
sleep 3

# 4. Test ręczny
sudo -u kiosk DISPLAY=:0 chromium-browser \
  --kiosk \
  --no-first-run \
  --ignore-certificate-errors \
  "https://100.64.0.7:3001?deviceId=$(hostname)"

# Jeśli działa ręcznie, restart usługi:
sudo systemctl start gastro-kiosk.service

# Jeśli crash nadal - reinstalacja chromium
sudo apt remove --purge chromium-browser
sudo apt autoremove
sudo apt install chromium-browser
sudo reboot
```

---

## KATEGORIA 5: FUNCTIONAL ISSUES

### Problem: Device ID nieprawidłowy

**Objawy**:
- CARD payment niedostępny mimo że terminal zainstalowany
- `/api/devices/me` zwraca 404
- Device-manager nie widzi urządzenia

**Rozwiązanie**:
```bash
# 1. Sprawdź URL w przeglądarce
# Naciśnij F12 → Network → sprawdź URL
# Powinno być: ?deviceId=HOSTNAME

# 2. Sprawdź localStorage
# F12 → Application → Local Storage
# Sprawdź: kiosk_device_id = ?

# 3. Jeśli brak lub nieprawidłowy - popraw URL w service
sudo nano /usr/local/bin/gastro-kiosk-start.sh

# Znajdź linię:
# URL="https://${SERVER_IP}:${SERVER_PORT}?deviceId=${DEVICE_HOSTNAME}"

# Sprawdź czy zmienna DEVICE_HOSTNAME jest prawidłowa
# Powinna być ustawiona w /etc/systemd/system/gastro-kiosk.service

sudo nano /etc/systemd/system/gastro-kiosk.service
# Dodaj/popraw:
# Environment="DEVICE_HOSTNAME=kiosk01"  # lub inna nazwa

# Reload i restart
sudo systemctl daemon-reload
sudo systemctl restart gastro-kiosk.service
```

---

### Problem: Drukarka/terminal nie wykrywane

**Objawy**:
- Hardware podłączony ale aplikacja go nie widzi
- CARD payment niedostępny
- Wydruki nie działają

**Rozwiązanie**:
```bash
# 1. Sprawdź czy usługi heartbeat działają
systemctl status gastro-printer.service
systemctl status gastro-terminal.service

# Jeśli "inactive" - uruchom:
sudo systemctl start gastro-printer.service
sudo systemctl start gastro-terminal.service

# Jeśli "failed" - sprawdź logi:
journalctl -u gastro-printer.service -n 20

# 2. Sprawdź czy wysyłają heartbeat
# Logi powinny pokazać co 30s:
# "Sending heartbeat to device-manager"

# 3. Test manualny rejestracji
curl -X POST http://100.64.0.7:8090/register \
  -H "Content-Type: application/json" \
  -d '{
    "deviceId": "'$(hostname)'",
    "capabilities": {
      "printer": true,
      "paymentTerminal": true
    },
    "timestamp": '$(date +%s)'000'
  }'

# 4. Sprawdź czy device-manager widzi
curl http://100.64.0.7:8090/devices/$(hostname)

# Powinno zwrócić:
# {
#   "deviceId": "kiosk01",
#   "capabilities": { "printer": true, "paymentTerminal": true },
#   "online": true
# }

# 5. Jeśli nadal nie działa - sprawdź DEVICE_MANAGER_URL
cat /etc/systemd/system/gastro-printer.service | grep DEVICE_MANAGER_URL
# Powinno być: http://100.64.0.7:8090

# Jeśli nieprawidłowy:
sudo nano /etc/systemd/system/gastro-printer.service
# Popraw: Environment="DEVICE_MANAGER_URL=http://100.64.0.7:8090"
sudo systemctl daemon-reload
sudo systemctl restart gastro-printer.service
```

---

### Problem: IDLE screen nie działa

**Objawy**:
- Aplikacja nie pokazuje ekranu powitalnego
- LUB IDLE nie wraca po 60s

**To NIE jest błąd!** 

IDLE screen:
- Działa tylko na Customer Kiosk (port 3001)
- NIE działa na Cashier (3003) ani Display (3002)
- Timeout: 60 sekund bez aktywności

**Jeśli IDLE naprawdę nie działa**:
```bash
# Sprawdź URL
# F12 → Network → sprawdź czy to port 3001

# Sprawdź console logi
# F12 → Console → szukaj "[IDLE]"

# Hard refresh (wyczyść cache)
Ctrl+Shift+R
```

---

## EMERGENCY PROCEDURES

### Procedura 1: Pełny restart systemu

```bash
# Zatrzymaj wszystkie usługi
sudo systemctl stop gastro-kiosk.service
sudo systemctl stop gastro-printer.service
sudo systemctl stop gastro-terminal.service

# Wyczyść procesy
pkill -9 chromium
pkill -9 node

# Restart
sudo reboot
```

---

### Procedura 2: Factory reset (ostateczność)

```bash
# UWAGA: To usuwa całą konfigurację!

# 1. Backup (opcjonalnie)
sudo tar -czf /tmp/kiosk-backup-$(date +%Y%m%d).tar.gz \
  /etc/systemd/system/gastro-*.service \
  /usr/local/bin/gastro-*

# 2. Zatrzymaj usługi
sudo systemctl stop gastro-kiosk.service
sudo systemctl disable gastro-kiosk.service

# 3. Usuń pliki
sudo rm -rf /etc/systemd/system/gastro-*.service
sudo rm -rf /usr/local/bin/gastro-*
sudo rm -rf /home/kiosk/printer-service
sudo rm -rf /home/kiosk/payment-terminal-service

# 4. Odłącz VPN
sudo tailscale down
sudo tailscale logout

# 5. Reinstalacja
# Uruchom kiosk-install-v2.sh ponownie
sudo bash kiosk-install-v2.sh
```

---

## LOGI I DIAGNOSTYKA

### Lokalizacje plików logów

```bash
# Instalacja
/var/log/gastro-kiosk-install.log

# Startup skryptu
/var/log/gastro-kiosk-startup.log

# Systemd service
journalctl -u gastro-kiosk.service

# LightDM
journalctl -u lightdm

# X11
/var/log/Xorg.0.log

# Tailscale
sudo tailscale status
journalctl -u tailscaled
```

### Zbieranie logów dla supportu

```bash
# Kompletny zestaw diagnostyczny
sudo bash -c 'cat > /tmp/diagnostic.txt << EOF
=== SYSTEM INFO ===
$(uname -a)
$(lsb_release -a)

=== SERVICES ===
$(systemctl status gastro-kiosk.service)
$(systemctl status gastro-printer.service)
$(systemctl status gastro-terminal.service)
$(systemctl status lightdm)

=== VPN ===
$(tailscale status)

=== PROCESSES ===
$(ps aux | grep chromium)
$(ps aux | grep node)

=== INSTALL LOG ===
$(tail -100 /var/log/gastro-kiosk-install.log)

=== STARTUP LOG ===
$(tail -100 /var/log/gastro-kiosk-startup.log)

=== JOURNALCTL ===
$(journalctl -u gastro-kiosk.service -n 100)

=== NETWORK ===
$(ip addr)
$(ip route)

=== DISK ===
$(df -h)
EOF
'

# Wyślij plik /tmp/diagnostic.txt do supportu
```

---

**Koniec Troubleshooting Guide**
