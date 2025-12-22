# Validation & Testing Procedure - Gastro Kiosk Pro

**Wersja**: 2.0.0  
**Data**: 2025-12-22  
**Czas wykonania**: 15-20 minut

Ten dokument zawiera kompletną procedurę testowania nowo zainstalowanego kiosku.

---

## TEST SUITE OVERVIEW

| Test ID | Kategoria | Priorytet | Czas |
|---------|-----------|-----------|------|
| T1 | Boot & Login | KRYTYCZNY | 2 min |
| T2 | Display & GUI | KRYTYCZNY | 2 min |
| T3 | Network & VPN | KRYTYCZNY | 3 min |
| T4 | Application Load | KRYTYCZNY | 2 min |
| T5 | Touch Interface | WYSOKI | 3 min |
| T6 | Device Registration | WYSOKI | 2 min |
| T7 | Order Flow | WYSOKI | 5 min |
| T8 | Hardware (Printer) | ŚREDNI | 3 min |
| T9 | Hardware (Terminal) | ŚREDNI | 5 min |
| T10 | Security & Access | NISKI | 2 min |

**Łączny czas**: ~30 minut (z opcjonalnymi testami hardware)

---

## PRE-TEST CHECKLIST

### Przed rozpoczęciem testów:

- [ ] Urządzenie zrestartowane po instalacji
- [ ] Masz dostęp SSH z laptopa (opcjonalnie)
- [ ] Masz authkey zapisany (do weryfikacji VPN)
- [ ] Znasz hostname urządzenia (np. kiosk01)
- [ ] Masz kartę testową (jeśli test terminala)
- [ ] Drukarka ma papier (jeśli test drukarki)

---

## TEST 1: BOOT & LOGIN (KRYTYCZNY)

### Cel: Sprawdzić czy urządzenie bootuje i loguje się automatycznie

**Kroki**:
```
1. Włącz urządzenie (jeśli wyłączone)
2. Obserwuj proces bootu
3. Zmierz czas od włączenia do załadowania aplikacji
```

**Expected Result**:
- [ ] GRUB bootloader pojawia się (2-3s)
- [ ] Ubuntu boot screen (5-10s)
- [ ] Auto-login wykonany (bez ekranu logowania)
- [ ] Openbox desktop załadowany
- [ ] Chromium otwiera się automatycznie w kiosk mode
- [ ] Aplikacja załadowana (ekran IDLE lub menu)

**Timing**:
- Boot do login: 10-20s
- Login do aplikacji: 5-10s
- **Łączny czas: 15-30s**

**FAIL Scenarios**:
❌ **Login screen pojawia się** → Auto-login nie działa (sprawdź /etc/lightdm/lightdm.conf.d/)  
❌ **Czarny ekran** → Display manager nie działa (sprawdź systemctl status lightdm)  
❌ **Openbox bez aplikacji** → Systemd service nie działa (sprawdź journalctl -u gastro-kiosk)

**Test Status**: ⬜ PASS / ⬜ FAIL  
**Notatki**: _______________________________________________

---

## TEST 2: DISPLAY & GUI (KRYTYCZNY)

### Cel: Sprawdzić środowisko graficzne i kiosk mode

**Kroki**:
```
1. Sprawdź rozdzielczość ekranu
2. Sprawdź czy aplikacja jest fullscreen
3. Sprawdź czy kursor jest ukryty
4. Spróbuj wyjść z aplikacji (Alt+F4, Esc)
```

**Expected Result**:
- [ ] Aplikacja wypełnia cały ekran (fullscreen)
- [ ] Brak paska zadań / menu
- [ ] Brak kursora myszy (ukryty automatycznie)
- [ ] Nie można wyjść z aplikacji (kiosk mode)
- [ ] Alt+F4 nie działa
- [ ] Esc nie działa
- [ ] Prawy przycisk myszy nie działa (jeśli testujemy myszką)

**Rozdzielczość**:
```bash
# SSH test (opcjonalnie)
DISPLAY=:0 xrandr | grep "*"
```
Zapisz: _______________

**FAIL Scenarios**:
❌ **Widoczny pasek zadań** → Chromium nie w kiosk mode  
❌ **Widoczny kursor** → Unclutter nie działa  
❌ **Można wyjść (Alt+F4)** → Flagi chromium nieprawidłowe

**Test Status**: ⬜ PASS / ⬜ FAIL  
**Notatki**: _______________________________________________

---

## TEST 3: NETWORK & VPN (KRYTYCZNY)

### Cel: Sprawdzić połączenie sieciowe i VPN

**Test 3A: Internet Connectivity**
```bash
# SSH do urządzenia
ssh kiosk@<IP_LOKALNY>
# hasło: gastro2024

# Test 1: Ping Google
ping -c 3 8.8.8.8
```
**Expected**: 0% packet loss

**Test 3B: DNS Resolution**
```bash
nslookup google.com
```
**Expected**: Zwraca IP Google

**Test 3C: VPN Status**
```bash
sudo tailscale status
```
**Expected Result**:
- [ ] Status: "Running"
- [ ] Serwer widoczny: 100.64.0.7 kiosk-server
- [ ] Status serwera: "online"
- [ ] Urządzenie ma IP: 100.64.0.X

Zapisz IP VPN: _______________

**Test 3D: Backend Connectivity**
```bash
# Test backend health
curl -k https://100.64.0.7:3000/api/health

# Expected: {"status":"ok"}
```

**Test 3E: Frontend Connectivity**
```bash
# Test frontend
curl -k -I https://100.64.0.7:3001

# Expected: HTTP/1.1 200 OK
```

**FAIL Scenarios**:
❌ **Ping 8.8.8.8 failed** → Brak internetu (sprawdź Ethernet)  
❌ **Tailscale stopped** → VPN nie połączony (sprawdź authkey)  
❌ **Backend failed** → Problem serwera (sprawdź docker na kiosk-server)

**Test Status**: ⬜ PASS / ⬜ FAIL  
**Notatki**: _______________________________________________

---

## TEST 4: APPLICATION LOAD (KRYTYCZNY)

### Cel: Sprawdzić czy aplikacja ładuje się poprawnie

**Test 4A: Visual Inspection**
```
1. Sprawdź czy widać logo/branding
2. Sprawdź czy są kategorie produktów
3. Sprawdź czy zdjęcia produktów się ładują
```

**Expected Result**:
- [ ] Interfejs widoczny (nie biały ekran)
- [ ] Brak błędu "Cannot connect to server"
- [ ] Logo/branding widoczny
- [ ] Kategorie produktów załadowane (nie puste)
- [ ] Zdjęcia produktów się wyświetlają

**Test 4B: Console Logs (F12 jeśli klawiatura)**
```
1. Naciśnij F12 (jeśli masz klawiaturę)
2. Przejdź do Console
3. Sprawdź logi
```

**Expected Result**:
- [ ] Brak czerwonych błędów (errors)
- [ ] Log: "[DeviceContext] Device ID: kiosk01"
- [ ] Log: "[WebSocket] Connected"
- [ ] Log: "Products loaded: X items"

**Test 4C: Network Tab**
```
1. F12 → Network
2. Odśwież (Ctrl+R)
3. Sprawdź requesty
```

**Expected Result**:
- [ ] GET /api/categories → 200 OK
- [ ] GET /api/products → 200 OK
- [ ] WebSocket → 101 Switching Protocols
- [ ] Brak 404 / 500 błędów (oprócz /api/devices/me jeśli brak hardware)

**FAIL Scenarios**:
❌ **"Cannot connect to server"** → VPN/Backend problem  
❌ **Puste kategorie** → Backend błąd (sprawdź database)  
❌ **404 na wszystko** → Nginx routing problem

**Test Status**: ⬜ PASS / ⬜ FAIL  
**Notatki**: _______________________________________________

---

## TEST 5: TOUCH INTERFACE (WYSOKI)

### Cel: Sprawdzić czy ekran dotykowy działa poprawnie

**Test 5A: Basic Touch**
```
1. Dotknij kategorię produktu
2. Dotknij produkt
3. Dotknij przycisk "Dodaj do koszyka"
4. Dotknij ikonę koszyka
```

**Expected Result**:
- [ ] Każde dotknięcie reaguje natychmiast (<100ms delay)
- [ ] Wizualny feedback (ripple effect, highlight)
- [ ] Kategoria otwiera się
- [ ] Produkt dodaje się do koszyka
- [ ] Koszyk otwiera się

**Test 5B: Scrolling**
```
1. Przewiń listę produktów w górę
2. Przewiń listę produktów w dół
3. Szybkie przesunięcie (flick)
```

**Expected Result**:
- [ ] Scrolling płynny (smooth)
- [ ] Momentum scrolling działa (inercja)
- [ ] Brak "skipowania" (stuttering)
- [ ] Scrollbar ukryty (jeśli IDLE active)

**Test 5C: Multi-touch (jeśli wspierany)**
```
1. Dotknij ekran dwoma palcami
2. Spróbuj pinch-to-zoom (powinno NIE działać)
```

**Expected Result**:
- [ ] Pinch-to-zoom wyłączony (disabled)
- [ ] Multi-touch nie powoduje błędów

**Test 5D: Edge Cases**
```
1. Bardzo szybkie kliknięcia (double tap)
2. Przytrzymanie (long press)
3. Dotknięcie i przeciągnięcie
```

**Expected Result**:
- [ ] Double tap nie powoduje podwójnego dodania do koszyka
- [ ] Long press nie otwiera menu kontekstowego
- [ ] Drag nie powoduje "ghost clicks"

**FAIL Scenarios**:
❌ **Touch nie reaguje** → Touchscreen driver problem (sprawdź xinput)  
❌ **Opóźnienia >200ms** → Chromium/GPU problem  
❌ **Scrolling rwany** → Performance issue (RAM/CPU)

**Test Status**: ⬜ PASS / ⬜ FAIL  
**Notatki**: _______________________________________________

---

## TEST 6: DEVICE REGISTRATION (WYSOKI)

### Cel: Sprawdzić czy urządzenie jest zarejestrowane w device-manager

**Test 6A: Device ID in localStorage**
```
1. F12 → Application → Local Storage
2. Sprawdź klucz: kiosk_device_id
```

**Expected Result**:
- [ ] Klucz `kiosk_device_id` istnieje
- [ ] Wartość: hostname urządzenia (np. "kiosk01")

**Test 6B: Device-Manager API**
```bash
# SSH do urządzenia
curl http://100.64.0.7:8090/devices/$(hostname)
```

**Expected Result (jeśli BEZ hardware)**:
```json
{
  "error": "Device not found"
}
```
**To jest OK!** Urządzenia bez drukarki/terminala nie rejestrują się.

**Expected Result (jeśli Z hardware)**:
```json
{
  "deviceId": "kiosk01",
  "capabilities": {
    "printer": true,
    "paymentTerminal": true
  },
  "online": true,
  "lastSeen": 1234567890
}
```

**Test 6C: Backend API**
```bash
# Test capabilities endpoint
curl 'http://100.64.0.7:3000/api/devices/capabilities' \
  -H 'x-device-id: kiosk01'
```

**Expected Result (jeśli BEZ hardware)**:
```json
{
  "hasTerminal": false,
  "hasPrinter": false
}
```

**Expected Result (jeśli Z hardware)**:
```json
{
  "hasTerminal": true,
  "hasPrinter": true
}
```

**FAIL Scenarios**:
❌ **localStorage pusty** → URL nie ma ?deviceId  
❌ **Device-manager zwraca old data** → Heartbeat nie działa (sprawdź services)

**Test Status**: ⬜ PASS / ⬜ FAIL  
**Notatki**: _______________________________________________

---

## TEST 7: ORDER FLOW (WYSOKI)

### Cel: Sprawdzić pełny proces składania zamówienia

**Test 7A: Browse Products**
```
1. Wybierz kategorię (np. "Pizza")
2. Zobacz listę produktów
3. Sprawdź czy ceny widoczne
4. Sprawdź czy zdjęcia widoczne
```

**Expected Result**:
- [ ] Kategoria otwiera się (<500ms)
- [ ] Produkty załadowane (minimum 1)
- [ ] Każdy produkt ma: nazwę, cenę, zdjęcie
- [ ] Zdjęcia wyświetlają się (nie broken image)

**Test 7B: Add to Cart**
```
1. Kliknij produkt
2. Zobacz szczegóły (jeśli modal)
3. Kliknij "Dodaj do koszyka"
4. Sprawdź notyfikację
```

**Expected Result**:
- [ ] Szczegóły produktu widoczne (jeśli modal)
- [ ] Przycisk "Dodaj" działa
- [ ] Notyfikacja pojawia się: "Dodano do koszyka"
- [ ] Ikona koszyka pokazuje licznik (badge): "1"

**Test 7C: View Cart**
```
1. Kliknij ikonę koszyka
2. Zobacz koszyk
3. Sprawdź sumę
```

**Expected Result**:
- [ ] Koszyk otwiera się
- [ ] Produkt widoczny w koszyku
- [ ] Cena produktu poprawna
- [ ] Suma poprawna (z VAT)
- [ ] Przyciski: "Usuń", "Zmień ilość", "Przejdź do płatności"

**Test 7D: Modify Cart**
```
1. Zmień ilość produktu (+/-)
2. Usuń produkt (X)
3. Dodaj ponownie
```

**Expected Result**:
- [ ] Ilość się zmienia natychmiast
- [ ] Suma przelicza się automatycznie
- [ ] Usuń działa (produkt znika)
- [ ] Koszyk pusty po usunięciu (pokazuje "Koszyk jest pusty")

**Test 7E: Checkout - Order Type**
```
1. Dodaj produkt do koszyka
2. Kliknij "Przejdź do płatności"
3. Zobacz modal "Gdzie zjesz?"
```

**Expected Result**:
- [ ] Modal pojawia się (fullscreen)
- [ ] Opcje widoczne:
  - [ ] "Na miejscu" (dine-in)
  - [ ] "Na wynos" (takeaway)
- [ ] Można wybrać opcję
- [ ] Po wyborze, modal się zamyka
- [ ] Przejście do wyboru płatności

**Test 7F: Payment Method Selection**
```
1. Zobacz dostępne metody płatności
```

**Expected Result (BEZ terminala)**:
- [ ] CASH (gotówka) - widoczny
- [ ] CARD - NIE widoczny

**Expected Result (Z terminalem)**:
- [ ] CASH (gotówka) - widoczny
- [ ] CARD (terminal) - widoczny

**Test 7G: Place Order (CASH)**
```
1. Wybierz CASH
2. Kliknij "Złóż zamówienie"
3. Obserwuj
```

**Expected Result**:
- [ ] Zamówienie się wysyła (<1s)
- [ ] Ekran potwierdzeń pojawia się
- [ ] Numer zamówienia widoczny (np. #42)
- [ ] Komunikat: "Zamówienie przyjęte"
- [ ] Drukarka drukuje (jeśli zainstalowana)
- [ ] Po 5s → powrót do ekranu głównego

**FAIL Scenarios**:
❌ **Kategorie puste** → Backend/database problem  
❌ **Nie można dodać do koszyka** → Frontend bug  
❌ **Suma niepoprawna** → Calculation error  
❌ **Modal nie pojawia się** → OrderTypeModal disabled/missing  
❌ **Zamówienie nie wysyła się** → Backend API error

**Test Status**: ⬜ PASS / ⬜ FAIL  
**Notatki**: _______________________________________________

---

## TEST 8: HARDWARE - PRINTER (ŚREDNI)

### Warunki: Tylko jeśli drukarka zainstalowana

**Test 8A: Service Status**
```bash
# SSH
systemctl status gastro-printer.service
```

**Expected Result**:
- [ ] Status: "active (running)"
- [ ] Uptime: >1 minute
- [ ] Brak błędów w Status

**Test 8B: Heartbeat**
```bash
# Sprawdź logi (ostatnie 20 linii)
journalctl -u gastro-printer.service -n 20
```

**Expected Result**:
- [ ] Log co 30s: "Heartbeat sent"
- [ ] LUB log: "Registered with device-manager"
- [ ] Brak error logs

**Test 8C: Device-Manager Registration**
```bash
curl http://100.64.0.7:8090/devices/$(hostname)
```

**Expected Result**:
```json
{
  "capabilities": {
    "printer": true
  },
  "online": true
}
```

**Test 8D: Test Print**
```bash
# System test print
echo "TEST PRINT - $(date)" | lp

# Sprawdź czy wyszło
```

**Expected Result**:
- [ ] Komenda zwraca: "request id is ..."
- [ ] Drukarka drukuje w ciągu 3s
- [ ] Wydruk czytelny

**Test 8E: Order Print (Integration)**
```
1. Złóż zamówienie testowe (CASH)
2. Obserwuj drukarkę
```

**Expected Result**:
- [ ] Paragon drukuje się automatycznie po złożeniu zamówienia
- [ ] Paragon zawiera:
  - [ ] Numer zamówienia
  - [ ] Data/godzina
  - [ ] Lista produktów
  - [ ] Ceny
  - [ ] Suma
  - [ ] Typ zamówienia (Na miejscu/Na wynos)

**FAIL Scenarios**:
❌ **Service inactive** → Nie uruchomił się (sprawdź npm install)  
❌ **Device-manager not found** → Heartbeat nie działa (sprawdź URL)  
❌ **Test print failed** → Drukarka problem (sprawdź lsusb, papier)

**Test Status**: ⬜ PASS / ⬜ FAIL / ⬜ N/A (brak drukarki)  
**Notatki**: _______________________________________________

---

## TEST 9: HARDWARE - PAYMENT TERMINAL (ŚREDNI)

### Warunki: Tylko jeśli terminal zainstalowany

**Test 9A: Terminal Power**
```
1. Sprawdź terminal fizycznie
```

**Expected Result**:
- [ ] Terminal włączony (zielony ekran)
- [ ] Wyświetla: "UDP / PeP" lub "Ready"
- [ ] Kabel Ethernet podłączony (LED migają)

**Test 9B: Service Status**
```bash
# SSH
systemctl status gastro-terminal.service
```

**Expected Result**:
- [ ] Status: "active (running)"
- [ ] Uptime: >1 minute
- [ ] Brak błędów

**Test 9C: Network Connectivity**
```bash
# Sprawdź IP terminala (na terminalu: Menu → Zarządzanie → Wizytówka)
# Przykład: 10.42.0.75

ping -c 3 10.42.0.75
```

**Expected Result**:
- [ ] Ping successful (0% packet loss)
- [ ] RTT: <50ms

**Test 9D: Device-Manager Registration**
```bash
curl http://100.64.0.7:8090/devices/$(hostname)
```

**Expected Result**:
```json
{
  "capabilities": {
    "paymentTerminal": true
  },
  "online": true
}
```

**Test 9E: CARD Payment Available**
```
1. Dodaj produkt do koszyka
2. Przejdź do checkout
3. Wybierz typ zamówienia
4. Zobacz metody płatności
```

**Expected Result**:
- [ ] Opcja "CARD" (terminal) widoczna
- [ ] Można wybrać CARD

**Test 9F: Test Transaction (Optional - wymaga karty testowej)**
```
1. Złóż zamówienie z metodą CARD
2. Obserwuj
```

**Expected Result**:
- [ ] Modal "Płatność kartą" pojawia się
- [ ] Modal pokazuje kwotę
- [ ] Modal pokazuje: "Przyłóż kartę do terminala"
- [ ] Terminal wyświetla kwotę
- [ ] Po przyłożeniu karty:
  - [ ] Terminal procesuje (3-5s)
  - [ ] Terminal pokazuje: "Zaakceptowano" (zielony checkmark)
  - [ ] Modal aktualizuje się: "Płatność zakończona sukcesem"
  - [ ] Paragon drukuje się
  - [ ] Powrót do ekranu głównego

**FAIL Scenarios**:
❌ **Terminal off** → Zasilanie problem  
❌ **Ping failed** → Sieć problem (sprawdź NAT, kabel)  
❌ **Service inactive** → Nie uruchomił się  
❌ **CARD nie widoczny** → Device-manager rejestracja failed  
❌ **Terminal timeout** → VPN problem lub terminal service błąd

**Test Status**: ⬜ PASS / ⬜ FAIL / ⬜ N/A (brak terminala)  
**Notatki**: _______________________________________________

---

## TEST 10: SECURITY & ACCESS (NISKI)

### Cel: Sprawdzić zabezpieczenia kiosku

**Test 10A: Kiosk Mode Escape**
```
Spróbuj wyjść z aplikacji różnymi metodami:
1. Alt+F4
2. Alt+Tab
3. Ctrl+Q
4. Esc
5. F11 (toggle fullscreen)
6. Prawy przycisk myszy
```

**Expected Result**:
- [ ] WSZYSTKIE powyższe NIE działają
- [ ] Nie można wyjść z aplikacji
- [ ] Nie można przełączyć do innej aplikacji

**Test 10B: TTY Access**
```
1. Naciśnij Ctrl+Alt+F2 (przełącz na TTY)
```

**Expected Result**:
- [ ] TTY pojawia się (czarny ekran z loginem)
- [ ] To jest OK - TTY dostęp jest normalny w Linux

**Aby wrócić**:
```
Ctrl+Alt+F7 (lub F1, zależnie od systemu)
```

**Test 10C: SSH Access**
```bash
# Z laptopa
ssh kiosk@<IP_VPN>
# hasło: gastro2024 (lub zmienione)
```

**Expected Result**:
- [ ] SSH działa
- [ ] Logowanie successful
- [ ] Dostęp do shell

**Test 10D: Sudo Access**
```bash
# W SSH
sudo -l
```

**Expected Result**:
- [ ] User kiosk ma sudo
- [ ] Prompt o hasło

**Test 10E: Auto-lock (opcjonalnie)**
```
1. Zostaw kiosk bez interakcji na 60s
```

**Expected Result (Customer Kiosk)**:
- [ ] Po 60s → IDLE screen pojawia się
- [ ] Ekran powitalny z logo
- [ ] Dotknięcie → powrót do menu

**Expected Result (Cashier/Display)**:
- [ ] Brak IDLE (aplikacja pozostaje widoczna)

**FAIL Scenarios**:
❌ **Można wyjść (Alt+F4)** → Flagi chromium źle  
❌ **SSH nie działa** → Firewall/sshd problem  
❌ **IDLE nie wraca** → Frontend bug (sprawdź console)

**Test Status**: ⬜ PASS / ⬜ FAIL  
**Notatki**: _______________________________________________

---

## FINAL VALIDATION REPORT

### Summary

**Urządzenie**: _______________  
**Data testu**: _______________  
**Tester**: _______________  
**Czas trwania**: _____ minut

### Results

| Test | Status | Notatki |
|------|--------|---------|
| T1: Boot & Login | ⬜ PASS / ⬜ FAIL | |
| T2: Display & GUI | ⬜ PASS / ⬜ FAIL | |
| T3: Network & VPN | ⬜ PASS / ⬜ FAIL | |
| T4: Application Load | ⬜ PASS / ⬜ FAIL | |
| T5: Touch Interface | ⬜ PASS / ⬜ FAIL | |
| T6: Device Registration | ⬜ PASS / ⬜ FAIL | |
| T7: Order Flow | ⬜ PASS / ⬜ FAIL | |
| T8: Printer | ⬜ PASS / ⬜ FAIL / ⬜ N/A | |
| T9: Terminal | ⬜ PASS / ⬜ FAIL / ⬜ N/A | |
| T10: Security | ⬜ PASS / ⬜ FAIL | |

### Overall Assessment

**Liczba testów PASS**: _____ / _____  
**Liczba testów FAIL**: _____  
**Success Rate**: _____ %

### Final Decision

⬜ **PASS** - Urządzenie gotowe do produkcji  
⬜ **CONDITIONAL PASS** - Drobne problemy, ale działające  
⬜ **FAIL** - Wymaga naprawy przed wdrożeniem

### Issues Found

```
1. _______________________________________________________________
2. _______________________________________________________________
3. _______________________________________________________________
```

### Action Items

```
1. _______________________________________________________________
2. _______________________________________________________________
3. _______________________________________________________________
```

### Sign-off

**Tester**: _______________  
**Podpis**: _______________  
**Data**: _______________

---

**Koniec Validation Procedure**
