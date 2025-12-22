# Quick Start Guide - Gastro Kiosk Installation

**Metoda**: LightDM + Systemd (Stabilna, Production-Ready)  
**Czas**: 5 minut przygotowania + 20 minut instalacji  
**Dla**: Ubuntu 22.04 / 24.04 LTS

---

## 🚀 NAJSZYBSZA ŚCIEŻKA (TL;DR)

```bash
# 1. Wygeneruj authkey na serwerze (kiosk-server)
ssh kiosk-server@192.168.31.139
headscale preauthkeys create --expiration 24h
# Skopiuj klucz!

# 2. Na nowym urządzeniu (świeże Ubuntu)
wget http://192.168.31.139/kiosk-install-v2.sh
# LUB skopiuj z pendrive

# 3. Uruchom
sudo bash kiosk-install-v2.sh

# 4. Odpowiedz na pytania:
# - Rola: 1 (Customer Kiosk)
# - Hostname: kiosk01
# - Username: kiosk (Enter)
# - Authkey: [wklej]
# - Drukarka: y/n (jeśli masz)
# - Terminal: y/n (jeśli masz)

# 5. Reboot
# Gotowe! Aplikacja uruchomi się automatycznie.
```

---

## 📋 PRZED INSTALACJĄ

### Krok 1: Przygotuj Headscale Authkey

Na serwerze **kiosk-server** (192.168.31.139):

```bash
ssh kiosk-server@192.168.31.139
# hasło: 1234

# Wygeneruj klucz (ważny 24h)
headscale preauthkeys create --expiration 24h

# Output:
# Key:     abcdef123456789...
# Expires: 2025-12-23 18:00:00
```

**ZAPISZ TEN KLUCZ!** Będzie potrzebny w kroku 4.

---

### Krok 2: Przygotuj nowe urządzenie

**Wymagania**:
- Ubuntu 22.04 lub 24.04 LTS (Desktop lub Server)
- Minimum 20GB dysku
- 2GB RAM (4GB zalecane)
- Połączenie Ethernet (WiFi możliwe ale nie zalecane)

**Instalacja Ubuntu**:
1. Boot z USB
2. Wybierz język: English (lub polski)
3. Instalacja: "Install Ubuntu"
4. Partycje: domyślne (cały dysk)
5. Użytkownik tymczasowy: dowolny (zostanie stworzony nowy)
6. Poczekaj na instalację (5-10 min)
7. Restart

---

### Krok 3: Zaktualizuj system

Po pierwszym uruchomieniu Ubuntu:

```bash
sudo apt update
sudo apt upgrade -y
```

**Czas**: 2-5 minut (zależnie od szybkości internetu)

---

## 🔧 INSTALACJA

### Krok 4: Pobierz i uruchom skrypt

**Opcja A: Pobierz z serwera** (najszybsze)

```bash
wget http://192.168.31.139/kiosk-install-v2.sh
# LUB jeśli serwer ma SSL:
curl -k -O https://192.168.31.139/kiosk-install-v2.sh
```

**Opcja B: Z pendrive** (bez internetu)

```bash
# Podłącz pendrive
# Skopiuj plik
cp /media/*/kiosk-install-v2.sh ~/
cd ~
```

**Opcja C: Z GitHub** (jeśli opublikowane)

```bash
wget https://raw.githubusercontent.com/USERNAME/REPO/main/scripts/kiosk-install-v2.sh
```

---

### Krok 5: Uruchom skrypt

```bash
# Nadaj uprawnienia
chmod +x kiosk-install-v2.sh

# Uruchom jako root
sudo bash kiosk-install-v2.sh
```

---

### Krok 6: Odpowiedz na pytania skryptu

Skrypt zapyta o:

#### Pytanie 1: Rola urządzenia
```
Select device role:
  1) Customer Kiosk (self-service ordering, port 3001)
  2) Cashier Admin (order management, port 3003)
  3) Display (status screen, port 3002)
Enter choice [1-3]: 
```

**Odpowiedź**: 
- `1` - dla kiosku samoobsługowego (najczęstsze)
- `2` - dla stanowiska kasjera
- `3` - dla wyświetlacza statusu

---

#### Pytanie 2: Hostname
```
Enter device hostname (e.g., kiosk01):
```

**Odpowiedź**: Unikalną nazwę, np.:
- `kiosk01`, `kiosk02` dla kolejnych kiosków
- `cashier01` dla kasjera
- `display01` dla wyświetlacza

**WAŻNE**: To będzie deviceId w systemie!

---

#### Pytanie 3: Username
```
Enter username for auto-login [kiosk]:
```

**Odpowiedź**: 
- Naciśnij **Enter** (zostaw domyślne: `kiosk`)
- LUB wpisz własną nazwę

**Hasło**: Skrypt ustawi `gastro2024` (możesz zmienić później)

---

#### Pytanie 4: Authkey
```
Enter Headscale authkey:
```

**Odpowiedź**: Wklej klucz wygenerowany w Kroku 1

**JAK WKLEIĆ**: Ctrl+Shift+V (lub prawy przycisk myszy → Paste)

---

#### Pytanie 5: Potwierdzenie
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

#### Pytanie 6-7: Hardware (opcjonalnie)
```
Install printer service? (y/N):
```
**Odpowiedź**: `y` tylko jeśli masz podłączoną drukarkę

```
Install payment terminal service? (y/N):
```
**Odpowiedź**: `y` tylko jeśli masz terminal płatniczy

---

### Krok 7: Czekaj na instalację

Skrypt wykona automatycznie 8 faz:

1. **System Preparation** - hostname, pakiety, user (2 min)
2. **Display Manager & GUI** - LightDM, Openbox (3 min)
3. **Chromium Browser** - touch support (2 min)
4. **VPN** - Tailscale + Headscale (1 min)
5. **Kiosk Service** - systemd service (1 min)
6. **Heartbeat Services** - printer/terminal (3 min, jeśli wybrano)
7. **Cleanup** - wyłączenie konfliktów (1 min)
8. **Validation** - testy (1 min)

**Łączny czas**: 15-20 minut

---

### Krok 8: Reboot

Po zakończeniu instalacji:

```
Reboot now? (y/N):
```

**Odpowiedź**: `y`

Urządzenie zrestartuje się.

---

## ✅ WERYFIKACJA

### Po restarcie

Urządzenie powinno:

1. ✅ **Automatycznie zalogować** się jako kiosk (bez ekranu logowania)
2. ✅ **Uruchomić Openbox** (lekkie środowisko graficzne)
3. ✅ **Otworzyć Chromium** w trybie kiosk (fullscreen)
4. ✅ **Załadować aplikację** Gastro Kiosk Pro

**Czas od włączenia do aplikacji**: 15-30 sekund

---

### Szybki test

**Test 1: Dotknij ekran**
- Aplikacja powinna reagować na dotyk
- Brak kursora myszy (ukryty)

**Test 2: Sprawdź połączenie**
- Kategorie produktów załadowane
- Zdjęcia produktów widoczne

**Test 3: Sprawdź device ID**
- Jeśli masz klawiaturę: F12 → Console
- Powinno być: `[DeviceContext] Device ID: kiosk01`

---

## 🔍 CO DALEJ?

### Pełne testy

Wykonaj kompletną procedurę testowania:

```bash
# Otwórz dokumentację testów
cat VALIDATION_TEST_PROCEDURE.md
```

10 zestawów testów obejmujących:
- Boot & Login
- Display & GUI  
- Network & VPN
- Application Load
- Touch Interface
- Device Registration
- Order Flow
- Hardware (drukarka/terminal)
- Security

---

### Management w produkcji

**Restart aplikacji** (bez pełnego rebootu):
```bash
ssh kiosk@<IP_VPN>
sudo systemctl restart gastro-kiosk.service
```

**Sprawdzenie statusu**:
```bash
systemctl status gastro-kiosk.service
```

**Logi live** (real-time):
```bash
journalctl -u gastro-kiosk.service -f
```

**Sprawdzenie VPN**:
```bash
sudo tailscale status
```

---

## 🆘 PROBLEMY?

### Czarny ekran po restarcie

```bash
# Przełącz na TTY: Ctrl+Alt+F2
# Zaloguj: kiosk / gastro2024

# Sprawdź display manager
sudo systemctl status lightdm

# Uruchom jeśli nie działa
sudo systemctl start lightdm

# Wróć do GUI: Ctrl+Alt+F7
```

---

### Aplikacja się nie uruchomiła

```bash
# SSH z innego urządzenia
ssh kiosk@<IP_VPN>

# Sprawdź status
systemctl status gastro-kiosk.service

# Sprawdź logi
journalctl -u gastro-kiosk.service -n 50

# Ręcznie uruchom
sudo systemctl start gastro-kiosk.service
```

---

### VPN nie połączony

```bash
# Sprawdź status
sudo tailscale status

# Restart VPN
sudo tailscale down
sudo tailscale up \
  --login-server="https://headscale.your-domain.com" \
  --authkey="NOWY_AUTHKEY" \
  --hostname="$(hostname)" \
  --accept-routes
```

---

### Więcej problemów?

Sprawdź kompletny przewodnik:

```bash
cat TROUBLESHOOTING_GUIDE.md
```

25 stron rozwiązań dla:
- Hardware
- Display Manager
- Network & VPN
- Service Issues
- Functional Issues

---

## 📚 DOKUMENTACJA

### Dostępne przewodniki:

1. **QUICK_START_GUIDE.md** (ten dokument)
   - Szybki start (5 minut)

2. **DEPLOYMENT_INSTRUCTIONS.md**
   - Szczegółowa instrukcja krok po kroku (30 stron)
   - Dla techników instalujących w terenie

3. **MANUAL_INSTALLATION_GUIDE.md**
   - Instalacja ręczna (bez skryptu)
   - Dla zaawansowanych użytkowników

4. **PRE_FLIGHT_CHECKLIST.md**
   - Checklist przed wyjazdem (12 stron)
   - Do wydruku dla techników

5. **VALIDATION_TEST_PROCEDURE.md**
   - 10 testów weryfikacyjnych (20 stron)
   - Procedury PASS/FAIL

6. **TROUBLESHOOTING_GUIDE.md**
   - Rozwiązywanie problemów (25 stron)
   - Najczęstsze błędy i naprawy

7. **AUTOSTART_METHODS_COMPARISON.md**
   - Analiza techniczna metod autostart
   - Dla developerów

---

## 🏭 WDROŻENIE PRODUKCYJNE

### Dla pojedynczego urządzenia

Postępuj według tego Quick Start Guide.

---

### Dla wielu urządzeń (5+)

**Przygotowanie**:
1. Wygeneruj **reusable authkey** (jeden klucz dla wszystkich):
   ```bash
   headscale preauthkeys create --expiration 24h --reusable
   ```

2. Przygotuj pendrive z:
   - `kiosk-install-v2.sh`
   - `authkey.txt` (klucz zapisany w pliku)
   - `DEPLOYMENT_INSTRUCTIONS.md` (wydrukowany)
   - `PRE_FLIGHT_CHECKLIST.md` (wydrukowany)

**Na miejscu**:
1. Podłącz pendrive
2. Uruchom skrypt
3. Użyj tego samego authkey dla wszystkich urządzeń
4. Zmień tylko hostname (kiosk01, kiosk02, ...)

**Tracking**:
- Wypełniaj checklist dla każdego urządzenia
- Zapisuj hostname i IP VPN w arkuszu Excel
- Wykonaj validation tests na każdym urządzeniu

---

### Dla korporacji (50+)

**Rozważ**:
1. **Ansible/Salt** - automatyczne wdrożenie
2. **Monitoring** - Uptime Kuma, Grafana
3. **Central logging** - syslog do centralnego serwera
4. **Backup config** - Git repository z konfiguracjami
5. **Staged rollout** - najpierw 5 urządzeń, potem reszta

**Kontakt**: Jeśli potrzebujesz pomocy z enterprise rollout

---

## 🎯 NAJCZĘSTSZE PYTANIA

### Q: Czy mogę użyć WiFi zamiast Ethernet?
**A**: Tak, ale Ethernet jest bardziej stabilny dla produkcji. WiFi może się rozłączać.

### Q: Czy muszę generować nowy authkey dla każdego urządzenia?
**A**: Nie, możesz użyć `--reusable` flag przy generowaniu klucza.

### Q: Co jeśli zapomniałem hasła użytkownika kiosk?
**A**: Domyślne hasło to `gastro2024`. Możesz je zmienić: `passwd`

### Q: Czy mogę zmienić hostname po instalacji?
**A**: Tak, ale lepiej reinstalować - hostname jest używany jako deviceId.

### Q: Jak zaktualizować aplikację?
**A**: Aktualizacja jest po stronie serwera (kiosk-server). Po update serwera, urządzenia automatycznie pobiorą nową wersję.

### Q: Czy skrypt działa na Raspberry Pi?
**A**: Nie testowane. Zaprojektowane dla x86_64 Ubuntu. ARM może wymagać modyfikacji.

### Q: Jak dodać drukarkę/terminal później?
**A**: Zainstaluj odpowiedni service ręcznie (patrz: MANUAL_INSTALLATION_GUIDE.md część 6).

---

## 📞 WSPARCIE

### Logi do wysłania przy problemach

```bash
# Zbierz logi
sudo bash -c 'cat > /tmp/diagnostic.txt << EOF
=== System Info ===
$(uname -a)
$(lsb_release -a)

=== Services ===
$(systemctl status gastro-kiosk.service)
$(systemctl status lightdm)

=== VPN ===
$(tailscale status)

=== Logs ===
$(tail -100 /var/log/gastro-kiosk-startup.log)
$(journalctl -u gastro-kiosk.service -n 100)
EOF
'

# Wyślij /tmp/diagnostic.txt
```

---

**KONIEC QUICK START GUIDE**

**Powodzenia z instalacją! 🚀**
