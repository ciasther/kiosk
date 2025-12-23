# Gastro Kiosk Pro - Instrukcja Wdrożenia Krok po Kroku

**Wersja**: 2.0.0  
**Data**: 2025-12-22  
**Dla**: Nowe urządzenia kiosk w lokalizacjach klientów  
**Czas trwania**: 20-30 minut  

---

## PRZED ROZPOCZĘCIEM - PRZYGOTOWANIE

### Na serwerze Headscale (kiosk-server)

**Krok 1: Wygeneruj nowy authkey**

```bash
# Zaloguj się na kiosk-server
ssh kiosk-server@192.168.31.139
# hasło: 1234

# Wygeneruj klucz ważny przez 24h, jednorazowy
headscale preauthkeys create --expiration 24h

# LUB dla kluczy wielokrotnego użytku (testowanie):
headscale preauthkeys create --expiration 24h --reusable
```

**ZAPISZ TEN KLUCZ!** Będzie potrzebny podczas instalacji.

Przykład wyjścia:
```
Key:     abcdef123456789abcdef123456789abcdef123456789
Expires: 2025-12-23 17:00:00
Reusable: false
```

---

### Pobierz skrypt instalacyjny

**Opcja A: Z GitHub (produkcja)**
```bash
wget https://raw.githubusercontent.com/yourusername/gastro-kiosk/main/scripts/kiosk-install-v2.sh
```

**Opcja B: Z lokalnego serwera**
```bash
# Na kiosk-server, skopiuj skrypt do nginx static files
scp /home/ciasther/webapp/bakery/scripts/kiosk-install-v2.sh \
    kiosk-server@192.168.31.139:/home/kiosk-server/gastro-kiosk-docker/static/

# Następnie na nowym urządzeniu:
wget http://192.168.31.139/kiosk-install-v2.sh
```

**Opcja C: Pendrive (brak internetu podczas instalacji)**
```bash
# Skopiuj skrypt na pendrive
# Następnie na nowym urządzeniu:
sudo cp /media/usb/kiosk-install-v2.sh /tmp/
cd /tmp
```

---

## INSTALACJA - KROK PO KROKU

### Krok 1: Przygotowanie nowego urządzenia

**1.1 Zainstaluj Ubuntu 22.04 LTS lub 24.04 LTS**

- Wersja: Desktop lub Server (Desktop zalecane dla łatwiejszego debugowania)
- Partycja: Minimum 20GB dysk
- Użytkownik tymczasowy: dowolny (zostanie stworzony nowy użytkownik "kiosk")
- Połączenie: Ethernet (WiFi NIE jest zalecane dla kiosków produkcyjnych)

**1.2 Zaktualizuj system**

```bash
sudo apt update
sudo apt upgrade -y
```

**1.3 Sprawdź połączenie internetowe**

```bash
ping -c 3 google.com
```

Jeśli nie ma internetu:
```bash
# Sprawdź interfejs
ip addr

# Skonfiguruj Ethernet (przykład)
sudo nano /etc/netplan/01-netcfg.yaml
```

---

### Krok 2: Pobierz i uruchom skrypt

**2.1 Pobierz skrypt (wybierz jedną metodę z sekcji wyżej)**

```bash
# Przykład: wget
wget https://your-server.com/kiosk-install-v2.sh

# Sprawdź czy pobrał się
ls -lh kiosk-install-v2.sh
```

**2.2 Nadaj uprawnienia wykonywania**

```bash
chmod +x kiosk-install-v2.sh
```

**2.3 Uruchom skrypt jako root**

```bash
sudo bash kiosk-install-v2.sh
```

---

### Krok 3: Odpowiadaj na pytania skryptu

Skrypt będzie zadawał pytania. Przygotuj odpowiedzi:

**Pytanie 1: Rola urządzenia**
```
Select device role:
  1) Customer Kiosk (self-service ordering, port 3001)
  2) Cashier Admin (order management, port 3003)
  3) Display (status screen, port 3002)
Enter choice [1-3]:
```

**Odpowiedz**:
- `1` - dla kiosku samoobsługowego (najczęstsze)
- `2` - dla stanowiska kasjera
- `3` - dla wyświetlacza statusu zamówień

---

**Pytanie 2: Hostname urządzenia**
```
Enter device hostname (e.g., kiosk01):
```

**Odpowiedz**: Unikalną nazwę, np.:
- `kiosk01`, `kiosk02`, `kiosk03` - dla kiosków
- `cashier01` - dla kasjera
- `display01` - dla wyświetlacza

**WAŻNE**: Ta nazwa będzie widoczna w systemie jako deviceId!

---

**Pytanie 3: Nazwa użytkownika**
```
Enter username for auto-login [kiosk]:
```

**Odpowiedz**: 
- Naciśnij Enter (zostaw domyślne: `kiosk`)
- LUB wpisz własną nazwę (np. `gastro`, `bakery`)

**Hasło**: Skrypt ustawi hasło `gastro2024` (można zmienić później)

---

**Pytanie 4: Headscale authkey**
```
Enter Headscale authkey:
```

**Odpowiedz**: Wklej klucz wygenerowany w Kroku 1

**JAK WKLEIĆ**:
- Klawiatura: Ctrl+Shift+V
- Touchscreen: Użyj klawiatury ekranowej (jeśli jest) lub SSH z laptopa
- Najlepiej: Zaloguj się przez SSH z laptopa i wklej tam

---

**Pytanie 5: Potwierdzenie konfiguracji**
```
Configuration summary:
  Role: customer
  Hostname: kiosk01
  Username: kiosk
  URL: https://100.64.0.7:3001?deviceId=kiosk01

Proceed with installation? (y/N):
```

**Sprawdź dokładnie** wszystkie dane i wpisz: `y`

---

### Krok 4: Czekaj na instalację

Skrypt wykona automatycznie:

1. **Phase 1: System Preparation** (2 min)
   - Ustawienie hostname
   - Instalacja narzędzi (curl, git, htop)
   - Utworzenie użytkownika kiosk

2. **Phase 2: Display Manager & GUI** (3 min)
   - Instalacja LightDM (display manager)
   - Instalacja Openbox (window manager)
   - Konfiguracja auto-login

3. **Phase 3: Chromium Browser** (2 min)
   - Instalacja przeglądarki Chromium
   - Wsparcie dla ekranów dotykowych

4. **Phase 4: VPN** (1 min)
   - Instalacja Tailscale
   - Połączenie z serwerem Headscale
   - Testowanie połączenia VPN

5. **Phase 5: Kiosk Service** (1 min)
   - Utworzenie skryptu startowego
   - Konfiguracja systemd service
   - Włączenie autostartu

6. **Phase 6: Heartbeat Services** (opcjonalne, 3 min)
   - Instalacja Node.js
   - Konfiguracja usługi drukarki (jeśli masz drukarkę)
   - Konfiguracja usługi terminala płatniczego (jeśli masz terminal)

7. **Phase 7: Cleanup** (1 min)
   - Wyłączenie starych autostartów
   - Czyszczenie cache

8. **Phase 8: Validation** (1 min)
   - Sprawdzenie czy wszystko zainstalowane poprawnie

---

### Krok 5: Opcjonalne usługi heartbeat

**Pytanie 6: Drukarka**
```
Install printer service? (y/N):
```

**Odpowiedz**:
- `y` - jeśli urządzenie ma podłączoną drukarkę (np. Hwasung)
- `n` - jeśli urządzenie NIE ma drukarki (większość przypadków)

---

**Pytanie 7: Terminal płatniczy**
```
Install payment terminal service? (y/N):
```

**Odpowiedz**:
- `y` - jeśli urządzenie ma terminal płatniczy (np. Ingenico Self 2000)
- `n` - jeśli urządzenie NIE ma terminala

**WAŻNE**: Tylko kiosk samoobsługowy (Customer Kiosk) potrzebuje tych usług!

---

### Krok 6: Reboot

Po zakończeniu instalacji:

```
Installation complete. Please reboot manually when ready.
Reboot now? (y/N):
```

**Odpowiedz**: `y` (urządzenie zrestartuje się)

**LUB** jeśli chcesz coś jeszcze sprawdzić:

```bash
# Sprawdź logi
cat /var/log/gastro-kiosk-install.log

# Sprawdź czy usługa jest włączona
systemctl status gastro-kiosk.service

# Ręczny reboot później
sudo reboot
```

---

## PO RESTARCIE - WERYFIKACJA

### Krok 7: Sprawdź czy aplikacja działa

Po restarcie urządzenie powinno:

1. **Auto-login** - zalogować się automatycznie jako użytkownik `kiosk`
2. **Openbox** - uruchomić lekkie środowisko graficzne
3. **Chromium** - otworzyć przeglądarkę w trybie kiosk (fullscreen)
4. **Aplikacja** - załadować aplikację Gastro Kiosk Pro

**Co powinieneś zobaczyć**:
- Pełny ekran (fullscreen) bez paska zadań
- Interfejs aplikacji (ekran powitalny IDLE lub menu kategorii)
- Brak kursora myszy (ukryty automatycznie)
- Brak możliwości wyjścia do pulpitu (kiosk mode)

---

### Krok 8: Testowanie funkcjonalności

**Test 1: Ekran dotykowy**
```
✓ Dotknij ekran - interfejs powinien reagować
✓ Przewiń listę - scrolling powinien działać płynnie
✓ Naciśnij przycisk - powinien pokazać efekt kliknięcia
```

**Test 2: Połączenie z serwerem**
```
✓ Kategorie produktów załadowane (nie ma błędu połączenia)
✓ Zdjęcia produktów widoczne
✓ Aplikacja nie pokazuje "Cannot connect to server"
```

**Test 3: Device ID**
```
✓ Otwórz DevTools (jeśli masz klawiaturę: F12)
✓ Console → sprawdź czy jest: [DeviceContext] Device ID: kiosk01
✓ Application → Local Storage → kiosk_device_id powinno być: kiosk01
```

**Test 4: Heartbeat (jeśli zainstalowano)**
```bash
# SSH z laptopa do nowego urządzenia
ssh kiosk@<IP_URZADZENIA>
# hasło: gastro2024

# Sprawdź czy usługi działają
systemctl status gastro-printer.service
systemctl status gastro-terminal.service

# Sprawdź czy device-manager widzi urządzenie
curl http://100.64.0.7:8090/devices/kiosk01

# Powinno zwrócić JSON:
# {
#   "deviceId": "kiosk01",
#   "capabilities": {
#     "printer": true,
#     "paymentTerminal": true
#   },
#   "online": true
# }
```

---

## DEBUGOWANIE - GDY COŚ NIE DZIAŁA

### Problem 1: Czarny ekran po restarcie

**Przyczyna**: Display manager nie uruchomił się

**Rozwiązanie**:
```bash
# Przełącz się na TTY (Ctrl+Alt+F2)
# Zaloguj się jako kiosk / gastro2024

# Sprawdź status display managera
sudo systemctl status lightdm

# Jeśli nie działa, uruchom:
sudo systemctl start lightdm

# Sprawdź logi
sudo journalctl -u lightdm -n 50
```

---

### Problem 2: Aplikacja się nie uruchamia (widać pulpit)

**Przyczyna**: Systemd service nie wystartował

**Rozwiązanie**:
```bash
# Sprawdź status usługi
systemctl status gastro-kiosk.service

# Sprawdź logi
journalctl -u gastro-kiosk.service -n 50

# Ręcznie uruchom
sudo systemctl start gastro-kiosk.service

# Sprawdź logi startu
tail -f /var/log/gastro-kiosk-startup.log
```

**Typowe błędy**:
- `X11 server timeout` → Display manager nie działa (zobacz Problem 1)
- `VPN connection timeout` → Sprawdź authkey i połączenie z Headscale
- `Cannot reach server` → Sprawdź czy VPN połączony (tailscale status)

---

### Problem 3: VPN się nie łączy

**Przyczyna**: Nieprawidłowy authkey lub problem z Headscale

**Rozwiązanie**:
```bash
# Sprawdź status Tailscale
sudo tailscale status

# Jeśli nie połączony, spróbuj ponownie:
sudo tailscale down
sudo tailscale up \
    --login-server="https://headscale.your-domain.com" \
    --authkey="NOWY_AUTHKEY" \
    --hostname="kiosk01" \
    --accept-routes

# Sprawdź czy widzi serwer
sudo tailscale status | grep 100.64.0.7
```

**Na serwerze Headscale** (jeśli nie widzisz urządzenia):
```bash
# Sprawdź listę urządzeń
headscale nodes list

# Jeśli urządzenia nie ma, wygeneruj nowy klucz
headscale preauthkeys create --expiration 24h

# Zatwierdź urządzenie (jeśli wymaga approval)
headscale nodes register --key <NODE_KEY>
```

---

### Problem 4: Chromium otwiera wiele okien

**Przyczyna**: Konflikt z innymi metodami autostart

**Rozwiązanie**:
```bash
# Sprawdź ile procesów chromium
ps aux | grep chromium | grep -v grep

# Powinien być JEDEN proces. Jeśli więcej:

# Wyłącz XDG autostart
mv ~/.config/autostart/chromium.desktop \
   ~/.config/autostart/chromium.desktop.disabled

# Sprawdź openbox autostart
cat ~/.config/openbox/autostart

# Usuń linię z chromium jeśli jest (zostaw tylko xset, unclutter)
nano ~/.config/openbox/autostart

# Restart usługi
sudo systemctl restart gastro-kiosk.service
```

---

### Problem 5: Aplikacja pokazuje "Cannot connect"

**Przyczyna**: Brak połączenia z backend serwerem

**Rozwiązanie**:
```bash
# Test 1: Czy VPN działa
tailscale status | grep 100.64.0.7
# Powinno pokazać: 100.64.0.7  kiosk-server  ...  online

# Test 2: Czy backend odpowiada
curl -k https://100.64.0.7:3000/api/health
# Powinno zwrócić: {"status":"ok"}

# Test 3: Czy frontend dostępny
curl -k -I https://100.64.0.7:3001
# Powinno zwrócić: HTTP/1.1 200 OK

# Jeśli któryś test nie przechodzi, problem jest po stronie serwera
```

**Na serwerze (kiosk-server)**:
```bash
# Sprawdź kontenery Docker
docker ps

# Sprawdź logi backend
docker logs gastro_backend --tail 50

# Sprawdź logi nginx
docker logs gastro_nginx --tail 50
```

---

### Problem 6: Drukarka/terminal nie wykrywane

**Przyczyna**: Usługi heartbeat nie działają lub device-manager nie otrzymuje rejestracji

**Rozwiązanie**:
```bash
# Sprawdź usługi
systemctl status gastro-printer.service
systemctl status gastro-terminal.service

# Sprawdź logi
journalctl -u gastro-printer.service -n 20
journalctl -u gastro-terminal.service -n 20

# Test połączenia z device-manager
curl http://100.64.0.7:8090/health
# Powinno zwrócić: {"status":"ok"}

# Ręczna rejestracja (test) - UWAGA: używaj /heartbeat, nie /register
curl -X POST http://100.64.0.7:8090/heartbeat \
  -H "Content-Type: application/json" \
  -d '{
    "deviceId": "kiosk01",
    "capabilities": {"printer": true, "printerPort": 8083},
    "ip": "100.64.0.3",
    "hostname": "kiosk01"
  }'

# Sprawdź czy widzi urządzenie
curl http://100.64.0.7:8090/devices/kiosk01
```

**Automatyczna weryfikacja podczas instalacji**:

Skrypt `kiosk-install-v2.sh` w wersji 3.0.11+ zawiera rozszerzoną walidację (Phase 8), która automatycznie sprawdza:

✅ **Python Dependencies**: python-escpos, pillow
✅ **Node.js Modules**: express, cors, axios
✅ **Pliki**: print_ticket.py, server.js
✅ **Printer Service**: czy działa, czy odpowiada na port 8083
✅ **Heartbeat**: czy wysyła VPN IP (100.64.0.x) zamiast LAN (192.168.x.x)
✅ **Device-Manager**: czy urządzenie jest zarejestrowane
✅ **printerPort**: czy jest obecny w capabilities
✅ **Backend API**: czy wykrywa urządzenie

**Przykład output walidacji**:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PRINTER SERVICE VALIDATION (CRITICAL)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Checking Python dependencies...
  ✓ python-escpos installed
  ✓ pillow installed
  ✓ print_ticket.py exists
  ✓ express module installed
  ✓ axios module installed
Starting printer service for validation...
  ✓ Printer service is running
Checking heartbeat...
  ✓ Heartbeat sent successfully
  ✓ Using VPN IP: 100.64.0.3
Checking device-manager registration...
  ✓ Device registered in device-manager
  ✓ printerPort: 8083
  ✓ Device-manager has VPN IP: 100.64.0.3
Testing printer HTTP endpoint...
  ✓ Printer service responds on port 8083
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✓ All validation checks passed!
```

**Weryfikacja ręczna (po reboot)**:
```bash
# 1. Sprawdź logi heartbeat - MUSI pokazywać VPN IP (100.64.0.x)
journalctl -u gastro-printer.service -n 5
# ✅ POPRAWNE: [Heartbeat] OK - kiosk01 @ 100.64.0.3
# ❌ BŁĄD: [Heartbeat] OK - kiosk01 @ 192.168.31.x (używa LAN!)

# 2. Sprawdź device-manager - MUSI mieć printerPort
curl http://100.64.0.7:8090/devices/kiosk01 | jq .
# ✅ POPRAWNE:
# {
#   "id": "kiosk01",
#   "printer": true,
#   "printerPort": "8083",   <-- MUSI BYĆ!
#   "ip": "100.64.0.3",       <-- VPN IP, nie 192.168.x!
#   "online": true
# }

# 3. Test wydruku
curl -X POST http://localhost:8083/test
# ✅ POPRAWNE: {"success":true,"message":"Test ticket printed"}
```

**Co robić jeśli walidacja FAILED**:

Skrypt wyświetli szczegółowe informacje o błędach i polecenia naprawcze.
Najczęstsze problemy:

1. **VPN nie połączony podczas instalacji**
   - Sprawdź: `tailscale status`
   - Napraw: `sudo tailscale up --login-server=... --authkey=...`

2. **Brakujące moduły Python**
   - Napraw: `pip3 install --break-system-packages python-escpos pillow`

3. **Heartbeat używa LAN IP zamiast VPN**
   - Sprawdź: `ip addr show tailscale0`
   - Jeśli brak interfejsu tailscale0, VPN nie działa
   - Uruchom ponownie skrypt lub napraw VPN

4. **printerPort brak w device-manager**
   - Oznacza starą wersję server.js
   - Uruchom ponownie instalację lub zaktualizuj ręcznie

---

## KOMENDY PRZYDATNE W PRODUKCJI

### Monitoring na urządzeniu

```bash
# Status głównej usługi
systemctl status gastro-kiosk.service

# Logi live (real-time)
journalctl -u gastro-kiosk.service -f

# Logi startup skryptu
tail -f /var/log/gastro-kiosk-startup.log

# Restart aplikacji (bez rebootu)
sudo systemctl restart gastro-kiosk.service

# Wyłączenie aplikacji (maintenance mode)
sudo systemctl stop gastro-kiosk.service

# Ponowne włączenie
sudo systemctl start gastro-kiosk.service
```

---

### Zdalny dostęp (SSH przez VPN)

```bash
# Z laptopa/serwera w sieci VPN:
ssh kiosk@100.64.0.X
# hasło: gastro2024

# Sprawdź IP urządzenia w VPN:
tailscale status | grep kiosk01
```

---

### Aktualizacja aplikacji (backend/frontend)

**NIE TRZEBA** aktualizować na urządzeniach kiosk!

Aplikacja ładuje się z serwera (kiosk-server), więc:
1. Zaktualizuj kod na kiosk-server
2. Zrestartuj kontenery Docker na kiosk-server
3. Odśwież stronę na kiosku (Ctrl+R) lub restart service

```bash
# Na urządzeniu kiosk (wymusza przeładowanie):
sudo systemctl restart gastro-kiosk.service
```

---

### Factory Reset (przywrócenie do stanu początkowego)

```bash
# UWAGA: To usunie całą konfigurację!

# Zatrzymaj usługi
sudo systemctl stop gastro-kiosk.service
sudo systemctl disable gastro-kiosk.service

# Usuń pliki konfiguracyjne
sudo rm -rf /usr/local/bin/gastro-kiosk-start.sh
sudo rm -rf /etc/systemd/system/gastro-kiosk.service
sudo rm -rf /home/kiosk/printer-service
sudo rm -rf /home/kiosk/payment-terminal-service

# Odłącz z VPN
sudo tailscale down
sudo tailscale logout

# Uruchom skrypt instalacyjny ponownie
sudo bash kiosk-install-v2.sh
```

---

## CHECKLIST - DO WYDRUKU

### Przed instalacją
- [ ] Ubuntu 22.04/24.04 zainstalowany
- [ ] Połączenie Ethernet aktywne
- [ ] Authkey Headscale wygenerowany i zapisany
- [ ] Hostname urządzenia ustalony (np. kiosk01)

### Podczas instalacji
- [ ] Skrypt pobrany i uruchomiony jako root
- [ ] Rola urządzenia wybrana (1=customer, 2=cashier, 3=display)
- [ ] Hostname podany
- [ ] Username zaakceptowany (kiosk)
- [ ] Authkey wklejony
- [ ] Potwierdzenie konfiguracji (y)
- [ ] Wszystkie fazy zakończone bez błędów
- [ ] Heartbeat services zainstalowane (jeśli masz hardware)
- [ ] Reboot wykonany

### Po restarcie
- [ ] Auto-login działa (kiosk/gastro2024)
- [ ] Chromium uruchomiony w kiosk mode (fullscreen)
- [ ] Aplikacja załadowana (widoczny interfejs)
- [ ] Ekran dotykowy reaguje
- [ ] VPN połączony (tailscale status)
- [ ] Device ID poprawny (F12 → Console)
- [ ] Backend dostępny (produkty się ładują)
- [ ] Drukarka wykryta (jeśli zainstalowano)
- [ ] Terminal płatniczy wykryty (jeśli zainstalowano)

### Oddanie do użytku
- [ ] Test zamówienia (dodaj produkt do koszyka)
- [ ] Test płatności (jeśli terminal)
- [ ] Test wydruku (jeśli drukarka)
- [ ] Test timeout IDLE (60s braku aktywności)
- [ ] Test multi-touch (jeśli wspierany)
- [ ] Dokumentacja pozostawiona (komendy, hasła)

---

## KONTAKT I WSPARCIE

### Logi do wysłania przy problemach

```bash
# Zbierz wszystkie logi do pliku
sudo bash -c 'cat /var/log/gastro-kiosk-install.log > /tmp/kiosk-debug.txt'
sudo bash -c 'echo "=== Startup Log ===" >> /tmp/kiosk-debug.txt'
sudo bash -c 'cat /var/log/gastro-kiosk-startup.log >> /tmp/kiosk-debug.txt'
sudo bash -c 'echo "=== Service Status ===" >> /tmp/kiosk-debug.txt'
sudo bash -c 'systemctl status gastro-kiosk.service >> /tmp/kiosk-debug.txt 2>&1'
sudo bash -c 'echo "=== Journalctl ===" >> /tmp/kiosk-debug.txt'
sudo bash -c 'journalctl -u gastro-kiosk.service -n 100 >> /tmp/kiosk-debug.txt'

# Plik gotowy do wysłania
cat /tmp/kiosk-debug.txt
```

---

**Koniec instrukcji - powodzenia z wdrożeniem!**
