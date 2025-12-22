# Gastro Kiosk Pro - System Memory & Architecture Guide

**Version**: 3.0.9-stable
**Status**: ✅ PRODUCTION READY - New device kioskvertical added
**Last Updated**: 2025-12-22 14:00
**Backup**: backup_working_20251220_120000.tar.gz

---

## 🎯 SUMMARY FOR NEW AI SESSIONS

**Read this file first!** It contains everything needed to work on Gastro Kiosk Pro:

1. **System Overview**: 4 devices, centralized architecture, payment terminal integration
2. **Access**: SSH credentials for all devices
3. **Critical Knowledge**: BCD encoding, packet parsing, payment flow
4. **Services**: What runs where, how to restart
5. **Troubleshooting**: Common issues and solutions
6. **History**: What was tried, what worked, what didn't
7. **Recent Fixes (2025-12-19)**: All WebSocket, chromium, keyboard issues resolved

**Key Files**:
- **[README.md](README.md)**: Main project documentation and Quick Start
- **[AGENTS.md](AGENTS.md)** (this file): Detailed system memory
- **[legacy_docs/](legacy_docs/)**: Archived documentation for old architecture
- **[pep_terminal_fixes/prompt.md](pep_terminal_fixes/prompt.md)**: Payment terminal debugging history

---

## 🏗️ SYSTEM ARCHITECTURE

### Central Server (kiosk-server)
- **IP**: 192.168.31.139 / 100.64.0.7 (VPN - Headscale)
- **SSH**: kiosk-server@192.168.31.139 (password: 1234)
- **Role**: Hosts ALL services in Docker containers.

**Docker Containers**:
1.  `gastro_nginx`: Reverse proxy, SSL, static file serving.
2.  `gastro_backend`: Node.js API, WebSocket, Payment logic.
3.  `gastro_device_manager`: Device heartbeat registry.
4.  `gastro_postgres`: PostgreSQL 16 database.
5.  `gastro_redis`: Redis 7 cache.

### Client Devices (Thin Clients)
- **kiosk** (192.168.31.35): **Cashier Admin Panel** (:3003) + On-Screen Keyboard
  - SSH: kiosk@192.168.31.35 (password: 2201)
  - Device ID: kiosk-CASHIER
  - Chromium autostart via `~/.config/autostart/gastro-kiosk.desktop`
- **admin1** (192.168.31.205 / 100.64.0.6 VPN): **Customer Kiosk** (:3001) + Payment Terminal + Printer
  - SSH: admin1@192.168.31.205 (password: 12345)
  - Device ID: admin1-RB102
  - Chromium autostart via `~/.config/openbox/autostart`
- **kiosk2** (192.168.31.170): **Order Status Display** (:3002)
  - SSH: kiosk2@192.168.31.170 (password: unknown)
- **kioskvertical** (100.64.0.9 VPN): **Customer Kiosk Vertical** (:3001)
  - SSH: kioskvertical@100.64.0.9 (password: 12345)
  - Device ID: kioskvertical
  - Display: 2160x3840 (Portrait/Vertical mode)
  - Chromium autostart via systemd `gastro-kiosk.service`

---

## 💳 PAYMENT TERMINAL INTEGRATION (CRITICAL)

### Terminal Hardware
- **Model**: Ingenico Self 2000
- **TID**: 01100460 (8-digit terminal ID)
- **MAC**: 10:1e:da:45:37:ce
- **IP**: 10.42.0.75 (via Ethernet through admin1 NAT)
- **Protocol**: UDP/PeP (Polskie ePłatności)
- **Test Environment**: 195.8.106.117

### CRITICAL: BCD Encoding & Packet Parsing
**Problem**: Terminal returned error 97 "Invalid transaction type"
**Root Cause**: TLV fields with format `n4` were sent as ASCII strings instead of BCD.
**Solution**: Implemented `encodeBCD()` function in `tlv.js`.

**Packet Parsing**:
- To terminal (UP00101): `STX UP00101 FS FS TLV_DATA ETX LRC`
- From terminal (UP10151): `STX UP10151 FS CODE FS TLV_DATA ETX LRC`
- From terminal (UP10052): Binding response with TID
- **Key**: UP1xxxx packets have a 2-digit CODE before the TLV data!

### CRITICAL: Terminal Binding (2025-12-19 Fix)
**Problem**: Terminal service couldn't bind to terminal after app updates
**Root Causes**:
1. Binding packet sent to wrong port (hardcoded 5000 instead of config.terminalPort)
2. UP10052 binding response packet not recognized
3. Broadcast address used direct IP instead of network broadcast
4. Binding timeout hardcoded instead of using config

**Solution**:
1. Fixed port in `bindTerminal()` to use `this.config.terminalPort`
2. Added UP10052 packet handler as binding response
3. Changed broadcast to use `10.42.0.255` (network broadcast)
4. Implemented fallback to use TERMINAL_IP from .env if no broadcast response
5. Made bindTimeout configurable via BIND_TIMEOUT env variable (default 10s)

**Files Modified**:
- `/home/admin1/payment-terminal-service/src/terminal/client.js`
- `/home/admin1/payment-terminal-service/server.js`
- `/home/admin1/payment-terminal-service/.env` (BIND_TIMEOUT=10000)

### Payment Flow
1.  Frontend initiates payment -> Backend creates transaction.
2.  Backend calls Terminal Service (on admin1).
3.  Terminal Service sends UDP packet to Terminal.
4.  Terminal displays instructions -> User taps card.
5.  Terminal sends result (UDP) -> Terminal Service.
6.  Terminal Service notifies Backend (Webhook).
7.  Backend notifies Frontend (WebSocket).

---

## 🤖 AUTOMATIC DEVICE DETECTION

### How It Works (Plug-and-Play)

**Device Registration Flow**:
1. Device starts with URL parameter: `?deviceId=HOSTNAME` (e.g., admin1-RB102)
2. DeviceContext saves to localStorage: `kiosk_device_id`
3. Payment/Printer services send heartbeat every 30s to device-manager
4. Device-manager merges capabilities (paymentTerminal, printer)
5. Frontend hooks (useDeviceCapabilities) query backend with deviceId
6. Backend queries device-manager for device capabilities
7. Frontend shows/hides payment methods based on capabilities

**Key Files**:
- `frontend/src/context/DeviceContext.tsx` - Saves deviceId from URL param
- `frontend/src/hooks/useDeviceCapabilities.ts` - Queries backend for capabilities
- `backend/src/routes/devices.js` - Queries device-manager dynamically
- `device-manager/server.js` - Merges capabilities from multiple services
- `payment-terminal-service/server.js` - Sends heartbeat with paymentTerminal=true
- `printer-service/server.js` - Sends heartbeat with printer=true

**Install Script**: `/home/ciasther/webapp/bakery/scripts/install-full-device-FIXED.sh`
- Automatically configures payment terminal service
- Automatically configures printer service
- Sets up systemd services with correct DEVICE_MANAGER_URL
- Configures autostart with deviceId parameter
- **Should work plug-and-play on new devices!**

**New Device Setup**:
```bash
# On new device with terminal + printer:
curl -O https://raw.githubusercontent.com/.../install-full-device-FIXED.sh
sudo bash install-full-device-FIXED.sh
# Reboot and done!
```

---

## 🔧 TROUBLESHOOTING

### Known Issues & Normal Behavior

#### "No token provided" Error (RESOLVED in v3.0.8)
**Symptom**: Error "No token provided" when clicking order actions, even though user is logged in
**Cause**: authStore used global axios without interceptor, while api.ts used axios.create() with interceptor
**Is this a problem?** ✅ FIXED - now all requests use same axios instance
**Solution**: 
- authStore now imports and uses `api` from `api.ts`
- All requests go through same interceptor
- Token added dynamically before every request
**Debugging**:
- Check console logs: `[API INTERCEPTOR] Request` should show token
- Uncomment `<DebugOverlay />` in App.tsx to see token state on screen
- Verify localStorage has token: DevTools → Application → localStorage → `token`

#### 404 on /api/devices/me (External devices without hardware)
**Symptom**: Console shows `GET /api/devices/me 404 (Not Found)`
**Cause**: Device doesn't have payment terminal or printer, so it's not registered in device-manager
**Is this a problem?** ❌ NO - This is **normal behavior**
**Result**: 
- Application works fine
- Can browse products and place orders
- CARD payment option won't show (only CASH/ONLINE)
- No local printing
**Action**: None needed - working as expected

#### WebSocket "Connecting to: " (empty URL)
**Symptom**: Console shows `[WebSocket] Connecting to:` with empty URL
**Cause**: Using default fallback (window.location)
**Is this a problem?** ❌ NO - This is **correct**
**Next line should show**: `[WebSocket] Connected, socket ID: ...`
**Action**: None needed - WebSocket works correctly

### Docker Services (kiosk-server)
```bash
# Check status
docker compose ps

# View logs
docker compose logs -f backend
docker compose logs -f device-manager

# Restart backend
docker compose restart backend
```

### Payment Terminal (admin1)
```bash
# Check service status
ssh admin1@192.168.31.205
sudo systemctl status payment-terminal.service
sudo systemctl status printer-service.service

# View logs
tail -f /home/admin1/payment-terminal-service/logs/service.log
tail -f /home/admin1/payment-terminal-service/logs/payment-terminal.log

# Check device registration
curl http://192.168.31.139:8090/devices/admin1-RB102
# Should show: paymentTerminal=true, printer=true, online=true
```

### Chromium Issues (admin1)

**Multiple chromium instances:**
```bash
# Check how many
ps aux | grep 'chromium.*https://' | grep -v grep | wc -l
# Should be: 1

# If more than 1, check for old services
systemctl list-unit-files | grep -E 'kiosk|bakery|chromium'
# Should all be: disabled

# Fix: disable old services
sudo systemctl disable kiosk-frontend.service bakery-kiosk-browser.service
sudo reboot
```

**Chromium restores old session:**
```bash
# Check if using temp profile
ps aux | grep chromium | grep 'user-data-dir=/tmp/chromium-kiosk'
# Should show the flag

# If not, check autostart
cat ~/.config/openbox/autostart | grep user-data-dir
# Should have: --user-data-dir=/tmp/chromium-kiosk
```

### Onboard Keyboard (admin1)

**Keyboard not showing:**
```bash
# Check if running
ps aux | grep onboard
# Should show 2 processes

# Check autostart
cat ~/.config/autostart/onboard.desktop
cat ~/.config/openbox/autostart | grep onboard

# Restart manually
killall onboard
DISPLAY=:0 onboard --xid &
```

**Keyboard too small/big:**
```bash
onboard-settings
# → Window → Size: adjust
# → Appearance → Key size: adjust
```

**Common Issues**:
- **Error 97**: Check BCD encoding.
- **Terminal Hanging**: Check WebSocket connection (must use `http://`, not `ws://`).
- **Timeout**: Terminal takes ~25s to send result after rejection. Frontend timer set to 60s.
- **Terminal Not Binding**: Service uses fallback to TERMINAL_IP if broadcast fails. Check terminal is on and responding to ping at 10.42.0.75.
- **Terminal Not Responding**: Terminal may need restart. Check terminal display shows "UDP / PEP" mode (Menu > Zarządzanie > Wizytówka).
- **CARD Payment Not Showing**: Check device-manager registration and frontend deviceId:
  ```bash
  # 1. Check device-manager
  curl http://192.168.31.139:8090/devices/DEVICE-ID
  # Should return: paymentTerminal: true
  
  # 2. Check backend API
  curl 'http://192.168.31.139:3000/api/devices/capabilities' \
    -H 'x-device-id: DEVICE-ID'
  # Should return: hasTerminal: true
  
  # 3. Check browser localStorage
  # Open DevTools → Application → localStorage
  # Should have: kiosk_device_id = "admin1-RB102"
  ```
- **Device Not Detected**: 
  - Check heartbeat services are running (payment-terminal + printer)
  - Check DEVICE_MANAGER_URL is correct (100.64.0.7:8090)
  - Check autostart has ?deviceId parameter
  - Device-manager expires devices after 60s without heartbeat

---

## 📋 VERSION HISTORY

### v3.0.9-stable (2025-12-22 14:00) ✅ CURRENT - NEW DEVICE KIOSKVERTICAL ADDED

**Status**: ✅ PRODUCTION READY - Vertical display device fully configured
**Backup**: backup_working_20251220_120000.tar.gz

#### Naprawy wykonane dzisiaj:

1. **New Device Setup - kioskvertical** ✅
   - Device: kioskvertical@100.64.0.9 (VPN only)
   - Role: Customer Kiosk (Vertical Display)
   - Display: 2160x3840 Portrait mode
   - URL: https://100.64.0.7:3001?deviceId=kioskvertical

2. **Display Manager Fix** ✅
   - Problem: Czarny ekran, brak środowiska graficznego
   - Root Cause: GDM3 był zamaskowany (masked)
   - Solution:
     - Unmask gdm3: `sudo systemctl unmask gdm3`
     - Unmask gdm: `sudo systemctl unmask gdm`
     - Daemon reload i enable gdm3
   - Result: X server działa na :0, rozdzielczość 2160x3840

3. **Chromium Autostart Fix** ✅
   - Problem: Uruchamiał się na :3002 (Display) zamiast :3001 (Customer Kiosk)
   - Solution:
     - Zaktualizowano `/usr/local/bin/gastro-kiosk-start.sh`
     - Zmieniono URL z :3002 na :3001
     - Dodano parametr deviceId=kioskvertical
     - Wyłączono duplikat w openbox autostart (renamed to .disabled)
   - Result: Pojedyncza instancja Chromium z poprawnym URL

4. **Service Configuration** ✅
   - Service: gastro-kiosk.service (już istniejący)
   - Status: enabled i running
   - Features:
     - Auto-restart on failure
     - VPN connection check przed uruchomieniem
     - Unclutter dla ukrycia kursora
     - Touch events enabled

#### Pliki zmodyfikowane:

**Device: kioskvertical (100.64.0.9)**:
- `/usr/local/bin/gastro-kiosk-start.sh` - zmieniono URL z :3002 na :3001
- `~/.config/openbox/autostart` - renamed to .disabled (zapobieganie duplikatom)
- `/etc/systemd/system/gastro-kiosk.service` - już skonfigurowany
- `/etc/systemd/system/gdm.service` - unmasked

#### Weryfikacja:

```bash
✅ Display Manager: GDM3 active i running
✅ X Server: Running on :0
✅ Display: 2160x3840 (Portrait mode)
✅ Chromium: 1 instancja w kiosk mode
✅ URL: https://100.64.0.7:3001?deviceId=kioskvertical
✅ VPN: Connected to 100.64.0.7
✅ Service: gastro-kiosk.service active
✅ Application: HTTP 200 OK
✅ Screenshot: Captured successfully
```

**Device Mapping (UPDATED)**:
- **kiosk** (192.168.31.35): Cashier Admin Panel (:3003)
- **admin1** (192.168.31.205): Customer Kiosk (:3001) + Terminal + Printer
- **kiosk2** (192.168.31.170): Order Status Display (:3002)
- **kioskvertical** (100.64.0.9): Customer Kiosk Vertical (:3001)

---

### v3.0.8-stable (2025-12-20 12:00) ✅ PREVIOUS - CASHIER & CUSTOMER KIOSK IMPROVEMENTS

**Status**: ✅ PRODUCTION READY - Cashier admin panel fully fixed and Customer Kiosk IDLE optimized
**Backup**: backup_working_20251220_120000.tar.gz

#### Naprawy wykonane dzisiaj:

1. **UI/UX Improvements** ✅
   - Zmieniono przyciski na polski: "ZAPŁACONO" (było "$$ PAID"), "ZAKOŃCZ" (było "NEXT >")
   - Usunięto niepotrzebny przycisk NEXT z kolumny "Awaiting Payment"
   - Poprawiono czytelność Dashboard (ciemniejszy tekst, więcej przestrzeni, mocniejsze cienie)
   - Dodano link do Reports w menu nawigacyjnym

2. **Critical Bug Fixes** ✅
   - Naprawiono błąd "t.map is not a function" w CreateOrderPage
   - Dodano bezpieczne parsowanie odpowiedzi API z `Array.isArray()` checks
   - Naprawiono ładowanie kategorii/produktów z backendu

3. **Authentication & Token Management** ✅
   - Naprawiono błąd "No token provided" przy klikaniu akcji zamówień
   - authStore teraz używa `api` zamiast globalnego `axios` (jedna instancja axios)
   - Dodano Axios request interceptor (token dodawany dynamicznie przed każdym żądaniem)
   - Dodano Axios response interceptor (automatyczne wylogowanie przy 401)
   - Dodano metodę `checkAuth()` w authStore dla synchronizacji stanu
   - Token działa poprawnie na wszystkich urządzeniach (kiosk, laptop, mobile)
   - Działa z tymczasowym localStorage (/tmp/chromium-kiosk)
   - Dodano debug logging (console.log) i DebugOverlay (wyłączony domyślnie)

4. **On-Screen Keyboard** ✅
   - Stworzono komponent OnScreenKeyboard dla LoginPage
   - Touch-friendly design (min 48px przyciski)
   - Pełna klawiatura: alfanumeryczne, znaki specjalne, Shift, Caps Lock, Backspace, Space, Enter
   - Dark theme pasujący do cashier UI
   - Pozycja fixed bottom z płynnymi animacjami

5. **Device Autostart Configuration** ✅
   - Usunięto chromium z `~/.config/openbox/autostart` (zostały tylko ustawienia systemowe)
   - Stworzono `~/.config/autostart/gastro-kiosk.desktop` z prawidłowymi flagami
   - Stworzono `~/.config/autostart/onboard-kiosk.desktop` dla klawiatury ekranowej
   - Dodano wersje `.disabled` dla łatwego włączania/wyłączania
   - Rezultat: pojedyncza instancja chromium z poprawnym URL (:3003)

6. **Customer Kiosk IDLE Screen** ✅
   - Aplikacja startuje z IDLE screen (nie czeka 60s)
   - Scrollbar ukryty podczas IDLE (body.idle-active class)
   - Pierwsze dotknięcie ekranu wyłącza IDLE
   - IDLE wraca po 60s braku aktywności

#### Pliki zmodyfikowane:

**Frontend (cashier-admin-frontend)**:
- `src/components/Orders/OrderCard.tsx` - etykiety przycisków i logika
- `src/components/Layout/MainLayout.tsx` - dodano link Reports, poprawiono styling
- `src/pages/DashboardPage.tsx` - poprawiono kontrast i spacing
- `src/pages/LoginPage.tsx` - zintegrowano OnScreenKeyboard
- `src/pages/CreateOrderPage.tsx` - bezpieczne parsowanie API
- `src/services/api.ts` - dodano interceptory request/response z logowaniem
- `src/stores/authStore.ts` - zmieniono na api zamiast axios, dodano checkAuth() i logi
- `src/App.tsx` - dodano useEffect dla sprawdzania auth
- `src/components/Keyboard/OnScreenKeyboard.tsx` - NOWY KOMPONENT
- `src/components/Debug/DebugOverlay.tsx` - NOWY (wyłączony domyślnie, do debugowania)
- `src/index.css` - poprawki globalnego motywu
- `src/i18n/locales/de.json`, `ua.json` - dodano tłumaczenie Reports

**Device Configuration (kiosk@192.168.31.35)**:
- `~/.config/openbox/autostart` - usunięto chromium
- `~/.config/autostart/gastro-kiosk.desktop` - chromium :3003 z prawidłowymi flagami
- `~/.config/autostart/onboard-kiosk.desktop` - klawiatura ekranowa
- `~/.config/autostart/onboard-kiosk.desktop.disabled` - backup do wyłączania

**Frontend (kiosk-client-frontend - Customer Kiosk :3001)**:
- `src/pages/HomePage.tsx` - start z IDLE, useEffect dla body class
- `src/index.css` - dodano `.idle-active { overflow: hidden }`

#### Weryfikacja:

```bash
Cashier Admin (:3003):
✅ UI: Polskie etykiety, czytelny dashboard, Reports w menu
✅ CreateOrderPage: ładuje kategorie/produkty bez błędów
✅ Auth: token się trzyma, automatyczne wylogowanie przy 401
✅ Keyboard: pojawia się na inputach logowania, touch-friendly
✅ Autostart: pojedyncza instancja chromium, poprawny URL (:3003)
✅ Printing: paragony drukują się przy zmianie statusu na READY

Customer Kiosk (:3001):
✅ IDLE: startuje od razu przy uruchomieniu aplikacji
✅ Scrollbar: ukryty podczas IDLE screen
✅ Touch: pierwsze dotknięcie wyłącza IDLE
✅ Timeout: IDLE wraca po 60s braku aktywności
```

**Device Mapping (POPRAWIONE)**:
- **kiosk** (192.168.31.35): Cashier Admin Panel (:3003)
- **admin1** (192.168.31.205): Customer Kiosk (:3001) + Terminal + Printer
- **kiosk2** (192.168.31.170): Order Status Display (:3002)

---

### v3.0.7-stable (2025-12-19 17:55) ✅ PREVIOUS - ALL SYSTEMS OPERATIONAL

**Status**: ✅ PRODUCTION READY - Wszystkie systemy działają poprawnie
**Backup**: backup_working_20251219_175427.tar.gz

#### Naprawy wykonane dzisiaj:

1. **Plug-and-Play Detection** ✅
   - Zaktualizowano `install-full-device-FIXED.sh` - dodano `?deviceId=$(hostname)` do URL
   - Nowe urządzenia automatycznie wykrywane bez konfiguracji serwera
   - Heartbeat services automatycznie rejestrują capabilities

2. **Chromium Autostart** ✅
   - Dodano `--user-data-dir=/tmp/chromium-kiosk` - czysty profil przy każdym starcie
   - Wyłączono stare serwisy: `kiosk-frontend.service`, `bakery-kiosk-browser.service`
   - Naprawiono problem podwójnego otwarcia (było: 2 chromium, jest: 1)
   - Admin1 teraz otwiera tylko :3001 z deviceId

3. **WebSocket Fix** ✅
   - Display (:3002): Naprawiono fallback w `useOrders.ts` - używa `window.location.host`
   - Cashier (:3003): Usunięto hardcoded `:3000` z `websocket.ts`
   - Oba frontendy używają dynamicznych URL przez nginx proxy
   - Real-time updates działają poprawnie

4. **Klawiatura Ekranowa** ✅
   - Zainstalowano **Onboard** na admin1
   - Skonfigurowano autostart w openbox
   - Dodano `--touch-events=enabled` do chromium
   - Automatyczne pokazywanie przy focus na input fields

5. **Cache i Sessions** ✅
   - Wyczyszczono chromium Sessions i Cache na admin1
   - Każdy restart = czysty profil dzięki `/tmp/chromium-kiosk`

#### Pliki zmodyfikowane:

**Kiosk-Server:**
- `display-client/src/hooks/useOrders.ts` - naprawiono WebSocket fallback
- `cashier-admin-frontend/src/services/websocket.ts` - usunięto hardcoded :3000
- `gastro-kiosk-docker/frontends/display/` - wdrożono nowy build
- `gastro-kiosk-docker/frontends/cashier/` - wdrożono nowy build

**Admin1:**
- `~/.config/openbox/autostart` - dodano onboard, --user-data-dir, --touch-events
- `~/.config/autostart/onboard.desktop` - autostart klawiatury
- Disabled: `kiosk-frontend.service`, `bakery-kiosk-browser.service`

**Dokumentacja:**
- `CHANGELOG.md` - v3.0.6 → v3.0.7
- `README.md` - plug-and-play section
- `install-full-device-FIXED.sh` - ?deviceId=$(hostname)
- Utworzono 6 raportów naprawczych

#### Weryfikacja:

```bash
✅ Chromium: 1 proces, czysty profil, poprawny URL
✅ WebSocket Display: brak błędów, Connected
✅ WebSocket Cashier: brak błędów, Connected  
✅ Onboard: 2 procesy, autostart działa
✅ Plug-and-play: deviceId automatyczny
✅ Device-manager: merguje capabilities
✅ Backend API: /api/devices/capabilities działa
```

#### Testy na zewnętrznym PC:

```bash
✅ GET /api/devices/me 404 - NORMALNE (brak terminala/drukarki)
✅ WebSocket Connected - DZIAŁA
✅ Aplikacja działająca - można składać zamówienia
✅ CARD payment NIE pokazuje się - POPRAWNIE (brak terminala)
```

**Wszystko działa zgodnie z oczekiwaniami!**

---

### v3.0.6-complete-fix (2025-12-19) ⚠️ POPRZEDNIA
- **Fixed**: Payment terminal not working after IP change
  - Root cause: kiosk-server IP changed from 100.64.0.4 to 100.64.0.7 (Headscale VPN)
  - Updated DEVICE_MANAGER_URL in all heartbeat services
  - Fixed device-manager merge logic (capabilities now merge instead of overwrite)
  - Fixed backend /api/devices/capabilities to query device-manager dynamically
  - Fixed payment controller terminalUrl variable
  - Fixed rate limiting (100 req/min) and trust proxy validation
- **Added**: OrderType selection modal
  - Fullscreen modal on checkout entry
  - Options: "Na miejscu" (dine-in) / "Na wynos" (takeaway)
  - Editable after selection
- **Fixed**: Payment flow for CARD
  - PaymentTerminalModal shows BEFORE printing
  - Real-time status from terminal via WebSocket
  - Automatic device detection through deviceId parameter
- **Fixed**: useDeviceCapabilities hook
  - Changed to use 'kiosk_device_id' from localStorage (was 'deviceId')
  - Enables automatic terminal detection on any device
- **Removed**: ONLINE payment method
- **Result**: Full payment terminal integration working! Plug-and-play device detection!

### v3.0.1-terminal-fix (2025-12-19) ✅
- **Fixed**: Terminal binding issues after app updates (VAT, etc.)
  - Fixed binding packet port (was hardcoded to 5000)
  - Added UP10052 packet recognition as binding response
  - Fixed broadcast address to use network broadcast (10.42.0.255)
  - Added fallback binding using TERMINAL_IP from .env
  - Made BIND_TIMEOUT configurable (10s default)
- **Device Mapping Update**: Corrected device roles (kiosk=customer, kiosk2=display)
- **Result**: Terminal binding works reliably, payments functional!

### v3.0.0-docker (2025-12-16) ✅
- **Complete migration to Docker**: All services containerized.
- **Centralized Architecture**: Single server, thin clients.
- **Auto-deployment**: Scripts for new devices.
- **Fixes**: Payment timeout increased to 60s, frontend smart detection.

### v2.1.0-pep-bcd-fix (2025-12-13) ✅
- **Fixed**: BCD encoding for PeP protocol (Error 97).
- **Fixed**: Packet parsing for terminal responses.
- **Result**: Successful card payments!

### v1.0 - v2.0 (Legacy)
- Initial development, systemd-based architecture.

---

## 🆕 RECENT FIXES (2025-12-19)

### Issue: Payment Terminal Not Working
**Symptom**: "Płatność nie powiodła się" error, CARD payment option not showing
**Root Cause**: Kiosk-server IP changed from 100.64.0.4 to 100.64.0.7
**Fixed**:
1. Updated all heartbeat services to use 100.64.0.7
2. Fixed device-manager merge logic
3. Fixed backend to query device-manager dynamically
4. Fixed useDeviceCapabilities to use 'kiosk_device_id'
5. Rate limiting increased to 100 req/min

### Issue: OrderType Selection Missing
**Symptom**: No option to select "Na miejscu" vs "Na wynos"
**Fixed**:
1. Added OrderTypeModal component (fullscreen on checkout entry)
2. Integrated with CheckoutPage
3. API accepts 'dine-in' / 'takeaway' → maps to DINE_IN / TAKEAWAY in DB

### Issue: Payment Prints Before Terminal
**Symptom**: For CARD payment, receipt printed immediately without terminal flow
**Fixed**:
1. Restored PaymentTerminalModal component
2. CARD flow now: Order → Terminal Modal → Terminal → Print → Confirm
3. CASH flow: Order → Print → Confirm

---

## 🔑 CRITICAL CONFIGURATION

### Device Manager URL (MUST BE CORRECT!)
**Current**: `http://100.64.0.7:8090`

**Update in**:
- `/etc/systemd/system/payment-terminal.service` (admin1)
- `/etc/systemd/system/printer-service.service` (admin1)
- Any new device install script

### Frontend Device ID
**CRITICAL**: URL parameter must include deviceId:
```
https://192.168.31.139:3001?deviceId=admin1-RB102
```

**Why**: DeviceContext saves this to `localStorage.kiosk_device_id`, which is used by useDeviceCapabilities hook to query backend for device capabilities.

**Without this**: Device will use hostname, which may not match device-manager registration, and terminal/printer won't be detected.

---

## 📝 DEPLOYMENT CHECKLIST (New Device)

When adding a new device with terminal/printer:

- [ ] Run install script: `install-full-device-FIXED.sh`
- [ ] Verify DEVICE_MANAGER_URL=http://100.64.0.7:8090
- [ ] Set DEVICE_ID to hostname (e.g., admin2-RB103)
- [ ] Configure autostart with ?deviceId parameter
- [ ] Test heartbeat: `curl http://192.168.31.139:8090/devices/DEVICE-ID`
- [ ] Test capabilities: `curl http://192.168.31.139:3000/api/devices/capabilities -H 'x-device-id: DEVICE-ID'`
- [ ] Test terminal binding: `curl http://localhost:8082/health`
- [ ] Test in browser: CARD payment option should appear
- [ ] Test payment flow: Order → Modal → Terminal → Success

---

