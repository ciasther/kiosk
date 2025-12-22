# Pre-Flight Checklist - Wdrożenie Kiosku

**Data wdrożenia**: _______________  
**Lokalizacja**: _______________  
**Technik**: _______________  
**Numer urządzenia**: _______________

---

## 1. PRZYGOTOWANIE SERWERA (WYKONAJ 1 DZIEŃ PRZED)

### A. Headscale Authkey
- [ ] Zalogowano na kiosk-server (192.168.31.139)
- [ ] Wygenerowano authkey: `headscale preauthkeys create --expiration 24h`
- [ ] Klucz zapisany w bezpiecznym miejscu (1Password/KeePass)
- [ ] Data ważności klucza: _______________

**Authkey**: `_________________________________________________`

### B. Weryfikacja serwera
- [ ] Sprawdzono czy backend działa: `curl -k https://100.64.0.7:3000/api/health`
- [ ] Sprawdzono czy device-manager działa: `curl http://100.64.0.7:8090/health`
- [ ] Sprawdzono czy kontenery Docker działają: `docker ps`
- [ ] Wszystkie 5 kontenerów online (backend, nginx, postgres, redis, device-manager)

### C. Przygotowanie skryptu
- [ ] Skrypt pobrany: `kiosk-install-v2.sh`
- [ ] Zapisany na pendrive (backup jeśli brak internetu)
- [ ] Sprawdzono uprawnienia: `chmod +x kiosk-install-v2.sh`

---

## 2. SPRZĘT I AKCESORIA (PRZED WYJAZDEM)

### A. Podstawowe
- [ ] Urządzenie kiosk (komputer/tablet z ekranem dotykowym)
- [ ] Kabel zasilający
- [ ] Kabel Ethernet (minimum 3m)
- [ ] Pendrive z skryptem instalacyjnym (backup)
- [ ] Laptop/tablet do zdalnego zarządzania (SSH)

### B. Opcjonalne (jeśli drukarka/terminal)
- [ ] Drukarka Hwasung + kabel USB
- [ ] Terminal płatniczy Ingenico Self 2000 + kabel Ethernet
- [ ] Rolki papieru termicznego (minimum 5 szt)
- [ ] Kabel Ethernet ekranowany do terminala

### C. Narzędzia
- [ ] Adapter USB-Ethernet (jeśli urządzenie nie ma portu)
- [ ] Klawiatura USB (do początkowej konfiguracji)
- [ ] Mysz USB (opcjonalnie, do debugowania)
- [ ] Śrubokręt (montaż kiosku)

### D. Dokumentacja
- [ ] Wydrukowana instrukcja wdrożenia (DEPLOYMENT_INSTRUCTIONS.md)
- [ ] Wydrukowany checklist (ten dokument)
- [ ] Karta kontaktowa z numerami alarmowymi

---

## 3. INFORMACJE O URZĄDZENIU

### A. Identyfikacja
**Hostname**: `_______________` (przykład: kiosk01, kiosk02)  
**Rola urządzenia** (zaznacz):
- [ ] Customer Kiosk (samoobsługowy, port 3001)
- [ ] Cashier Admin (kasjer, port 3003)
- [ ] Display (wyświetlacz statusu, port 3002)

**Dodatkowy hardware** (zaznacz):
- [ ] Drukarka Hwasung
- [ ] Terminal płatniczy Ingenico
- [ ] Nic (tylko ekran dotykowy)

### B. Sieć
**IP statyczne czy DHCP**: _______________  
**IP przypisany** (jeśli statyczne): _______________  
**Gateway**: _______________  
**DNS**: _______________

---

## 4. NA MIEJSCU - PRZED INSTALACJĄ

### A. Fizyczne połączenia
- [ ] Urządzenie podłączone do zasilania
- [ ] Kabel Ethernet podłączony i aktywny (migające LED)
- [ ] Ekran dotykowy włączony i reaguje
- [ ] Drukarka podłączona przez USB (jeśli dotyczy)
- [ ] Terminal podłączony przez Ethernet (jeśli dotyczy)

### B. Boot i system
- [ ] Ubuntu 22.04 lub 24.04 zainstalowany
- [ ] System uruchomiony i zalogowany
- [ ] Sprawdzono połączenie internetowe: `ping -c 3 google.com`
- [ ] Sprawdzono czy jest dostęp do portów: `sudo netstat -tulpn | grep LISTEN`

### C. Dostęp sieciowy
- [ ] Test HTTP: `curl -I http://google.com`
- [ ] Test DNS: `nslookup google.com`
- [ ] Test Headscale: `curl -I https://headscale.your-domain.com` (jeśli publiczne)

---

## 5. PODCZAS INSTALACJI

### A. Uruchomienie skryptu
- [ ] Skrypt skopiowany: `wget` lub z pendrive
- [ ] Uprawnienia nadane: `chmod +x kiosk-install-v2.sh`
- [ ] Uruchomiono jako root: `sudo bash kiosk-install-v2.sh`

### B. Odpowiedzi na pytania (ZAPISZ!)

**Pytanie 1 - Rola urządzenia**:  
Odpowiedź: `_____` (1/2/3)

**Pytanie 2 - Hostname**:  
Odpowiedź: `_______________`

**Pytanie 3 - Username**:  
Odpowiedź: `_______________` (domyślnie: kiosk)

**Pytanie 4 - Authkey**:  
Odpowiedź: `_________________________________________________`

**Pytanie 5 - Potwierdzenie**:  
Odpowiedź: `y`

**Pytanie 6 - Drukarka**:  
Odpowiedź: `_____` (y/n)

**Pytanie 7 - Terminal płatniczy**:  
Odpowiedź: `_____` (y/n)

### C. Fazy instalacji (zaznacz po zakończeniu)
- [ ] Phase 1: System Preparation (2 min)
- [ ] Phase 2: Display Manager & GUI (3 min)
- [ ] Phase 3: Chromium Browser (2 min)
- [ ] Phase 4: VPN (1 min)
- [ ] Phase 5: Kiosk Service (1 min)
- [ ] Phase 6: Heartbeat Services (3 min, jeśli dotyczy)
- [ ] Phase 7: Cleanup (1 min)
- [ ] Phase 8: Validation (1 min)

### D. Wynik walidacji
- [ ] ✓ User kiosk exists
- [ ] ✓ LightDM is enabled
- [ ] ✓ Chromium is installed
- [ ] ✓ VPN is connected (lub WARNING - will connect after reboot)
- [ ] ✓ Kiosk service is enabled
- [ ] ✓ Startup script is executable

**Liczba błędów**: _____ (powinno być: 0)

---

## 6. PO RESTARCIE

### A. Auto-start
- [ ] Urządzenie zrestartowane: `sudo reboot`
- [ ] Auto-login zadziałał (użytkownik: kiosk)
- [ ] Openbox uruchomiony (lekkie środowisko)
- [ ] Chromium otworzony automatycznie
- [ ] Chromium w trybie kiosk (fullscreen, brak paska zadań)
- [ ] Aplikacja załadowana (widoczny interfejs)

**Czas od bootu do aplikacji**: _____ sekund

### B. Weryfikacja interfejsu
- [ ] Ekran IDLE widoczny (jeśli Customer Kiosk)
- [ ] Logo/branding klienta widoczny
- [ ] Brak błędów "Cannot connect to server"
- [ ] Brak kursora myszy (ukryty)
- [ ] Kategorie produktów załadowane
- [ ] Zdjęcia produktów wyświetlają się

### C. Test ekranu dotykowego
- [ ] Dotknięcie ekranu reaguje
- [ ] Scrolling działa płynnie
- [ ] Przycisk "dodaj do koszyka" działa
- [ ] Przejście do koszyka działa
- [ ] Powrót do menu działa

---

## 7. TESTY FUNKCJONALNE

### A. Test VPN
```bash
ssh kiosk@<IP_LOKALNY>  # hasło: gastro2024
tailscale status | grep 100.64.0.7
```
- [ ] VPN połączony
- [ ] IP serwera widoczny: 100.64.0.7
- [ ] Status: "online"

**IP VPN urządzenia**: `_______________` (100.64.0.X)

### B. Test Device ID
- [ ] Otworzono DevTools (F12 jeśli klawiatura)
- [ ] Console → sprawdzono: `[DeviceContext] Device ID: _______________`
- [ ] Application → Local Storage → `kiosk_device_id` = `_______________`

### C. Test zamówienia (Customer Kiosk)
- [ ] Wybrano kategorię
- [ ] Dodano produkt do koszyka
- [ ] Przejście do checkout
- [ ] Modal "Gdzie zjesz?" pojawił się
- [ ] Wybrano "Na miejscu" lub "Na wynos"
- [ ] Wybrano metodę płatności

**Metody płatności widoczne**: 
- [ ] CASH (gotówka)
- [ ] CARD (terminal - tylko jeśli zainstalowano usługę)

### D. Test drukarki (jeśli zainstalowano)
- [ ] Drukarka włączona
- [ ] Papier załadowany
- [ ] Test wydruku z systemu: `echo "TEST" | lp`
- [ ] Usługa działa: `systemctl status gastro-printer.service`
- [ ] Device-manager widzi drukarkę: `curl http://100.64.0.7:8090/devices/<HOSTNAME>`

**Wynik**: 
```json
{
  "capabilities": {
    "printer": true
  }
}
```

### E. Test terminala płatniczego (jeśli zainstalowano)
- [ ] Terminal włączony
- [ ] Terminal w trybie UDP/PeP
- [ ] IP terminala: `_______________` (np. 10.42.0.75)
- [ ] Ping terminala działa: `ping <IP_TERMINALA>`
- [ ] Usługa działa: `systemctl status gastro-terminal.service`
- [ ] Device-manager widzi terminal: `curl http://100.64.0.7:8090/devices/<HOSTNAME>`

**Wynik**:
```json
{
  "capabilities": {
    "paymentTerminal": true
  }
}
```

**Test płatności testowej** (opcjonalnie):
- [ ] Złożono zamówienie z metodą CARD
- [ ] Modal terminala pojawił się
- [ ] Terminal wyświetlił kwotę
- [ ] Przyłożono kartę testową
- [ ] Płatność zaakceptowana
- [ ] Paragon wydrukowany

---

## 8. KONFIGURACJA KOŃCOWA

### A. Zmiana hasła (KONIECZNIE!)
```bash
ssh kiosk@<IP_VPN>  # hasło domyślne: gastro2024
passwd
# Ustaw NOWE hasło!
```
- [ ] Hasło zmienione
- [ ] Nowe hasło zapisane w 1Password/dokumentacji

**Nowe hasło**: `_______________` (NIE ZOSTAWIAJ W DOKUMENTACJI!)

### B. Monitoring
- [ ] Dodano urządzenie do listy monitorowanych (Uptime Kuma/Grafana)
- [ ] Sprawdzono logi: `journalctl -u gastro-kiosk.service -f`
- [ ] Brak błędów w logach

### C. Backup konfiguracji
```bash
# Zrób backup plików konfiguracyjnych
sudo tar -czf /tmp/kiosk-backup-$(date +%Y%m%d).tar.gz \
  /etc/systemd/system/gastro-kiosk.service \
  /usr/local/bin/gastro-kiosk-start.sh \
  /etc/lightdm/lightdm.conf.d/50-autologin.conf \
  /home/kiosk/.config/openbox/autostart

# Skopiuj na pendrive lub wyślij na serwer
```
- [ ] Backup wykonany
- [ ] Backup zapisany w lokalizacji: `_______________`

---

## 9. SZKOLENIE PERSONELU

### A. Podstawowe instrukcje
- [ ] Pokazano jak włączyć/wyłączyć urządzenie
- [ ] Pokazano jak zrestartować (w razie problemów)
- [ ] Pokazano jak wymieniać papier w drukarce (jeśli dotyczy)
- [ ] Pokazano jak restartować terminal (jeśli dotyczy)

### B. Obsługa kiosku
- [ ] Pokazano IDLE screen i sposób aktywacji
- [ ] Pokazano jak składać zamówienie (demonstracja)
- [ ] Pokazano obsługę płatności kartą (jeśli dotyczy)
- [ ] Pokazano jak pomóc klientowi przy problemach

### C. Kontakt alarmowy
- [ ] Podano numer telefonu do supportu technicznego
- [ ] Podano adres email do zgłoszeń
- [ ] Wyjaśniono procedurę zgłaszania awarii

**Numer alarmowy**: `_______________`  
**Email supportu**: `_______________`

---

## 10. DOKUMENTACJA I ODDANIE

### A. Dokumentacja techniczna
- [ ] Wypełniono wszystkie pola w tym checkliście
- [ ] Zapisano hostname, IP VPN, hasło w bazie urządzeń
- [ ] Wykonano screenshoty działającej aplikacji
- [ ] Zrobiono zdjęcie fizycznej instalacji (opcjonalne)

### B. Dokumentacja dla klienta
- [ ] Pozostawiono wydrukowane instrukcje obsługi
- [ ] Pozostawiono kartę kontaktową
- [ ] Pokazano jak uzyskać pomoc zdalną (jeśli SSH dostępny)

### C. Protokół odbioru
- [ ] Urządzenie działa zgodnie z oczekiwaniami
- [ ] Wszystkie testy zakończone sukcesem
- [ ] Klient/manager zaakceptował wdrożenie

**Podpis klienta**: _______________  
**Data oddania**: _______________  
**Godzina**: _______________

---

## 11. PROBLEMY I NOTATKI

### A. Napotkane problemy podczas instalacji
```
_______________________________________________________________
_______________________________________________________________
_______________________________________________________________
_______________________________________________________________
```

### B. Zastosowane rozwiązania
```
_______________________________________________________________
_______________________________________________________________
_______________________________________________________________
_______________________________________________________________
```

### C. Uwagi dotyczące lokalizacji
```
_______________________________________________________________
_______________________________________________________________
_______________________________________________________________
_______________________________________________________________
```

### D. Rekomendacje na przyszłość
```
_______________________________________________________________
_______________________________________________________________
_______________________________________________________________
_______________________________________________________________
```

---

## 12. QUICK REFERENCE - KOMENDY

### Sprawdzanie statusu
```bash
# Status głównej aplikacji
systemctl status gastro-kiosk.service

# Logi live
journalctl -u gastro-kiosk.service -f

# VPN status
tailscale status

# Czy backend odpowiada
curl -k https://100.64.0.7:3000/api/health
```

### Restart aplikacji
```bash
# Miękki restart (tylko aplikacja)
sudo systemctl restart gastro-kiosk.service

# Twardy restart (cały system)
sudo reboot
```

### Wyłączenie kiosku (maintenance)
```bash
# Stop aplikacji
sudo systemctl stop gastro-kiosk.service

# Wyjście z kiosk mode (tymczasowo)
# Naciśnij Alt+F4 kilka razy
# LUB Ctrl+Alt+F2 (przełącz na TTY)
```

---

**KONIEC CHECKLISTY**

**Wersja**: 2.0.0  
**Data utworzenia**: 2025-12-22  
**Ostatnia aktualizacja**: _______________
