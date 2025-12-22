# Gastro Kiosk Pro - System Zarządzania Zamówieniami

**Wersja**: 3.1.0-enterprise  
**Data**: 2025-12-22 17:30  
**Status**: ✅ PRODUCTION READY - ENTERPRISE INSTALLATION SYSTEM V2.0
**Backup**: backup_working_20251220_120000.tar.gz

---

## 🎯 System Overview

Kompletny system zarządzania zamówieniami dla gastronomii z integracją terminala płatniczego Polskie ePłatności (PeP).

### Komponenty:
- **Backend API** - Node.js/Express + PostgreSQL
- **Device Manager** - Dynamiczne wykrywanie urządzeń
- **Payment Terminal** - Ingenico Self 2000 (PeP Protocol)
- **Printer Service** - Drukowanie paragonów
- **Frontend** - React/TypeScript (kiosk, kasjer, kuchnia)

---

## 🆕 Co nowego w v3.0.9 (2025-12-22)

### Nowe urządzenie: kioskvertical (100.64.0.9)

✅ **Device Setup**
- Dodano nowe urządzenie z pionowym ekranem (2160x3840 Portrait)
- Rola: Customer Kiosk dla zamówień klientów
- URL: https://100.64.0.7:3001?deviceId=kioskvertical
- VPN only access (Headscale)

✅ **Display Manager Fix**
- Problem: Czarny ekran, brak GUI
- Rozwiązanie: Odmaskowano GDM3 (`systemctl unmask gdm3`)
- X server uruchomiony poprawnie na :0

✅ **Chromium Autostart Fix**
- Zmieniono URL z :3002 (Display) na :3001 (Customer Kiosk)
- Naprawiono duplikaty chromium (openbox autostart → disabled)
- Pojedyncza instancja z poprawnymi parametrami

✅ **Service Configuration**
- gastro-kiosk.service enabled i running
- Auto-restart on failure
- VPN connection check przed uruchomieniem
- Touch events enabled
- Automatyczne wylogowanie przy wygasłym tokenie (401)
- DebugOverlay component (wyłączony domyślnie) do debugowania

✅ **On-Screen Keyboard**
- Nowy komponent klawiatury ekranowej dla LoginPage
- Touch-friendly design (48px przyciski)
- Pełna klawiatura z Shift, Caps Lock, znakami specjalnymi

✅ **Device Autostart**
- Poprawiona konfiguracja autostart na urządzeniu kiosk
- Pojedyncza instancja chromium z poprawnym URL
- XDG autostart dla aplikacji, openbox dla ustawień systemowych

### Customer Kiosk (:3001) - IDLE Screen Improvements

✅ **IDLE Screen UX**
- Aplikacja startuje z IDLE screen (bez czekania 60s)
- Scrollbar ukryty podczas IDLE (body.idle-active class)
- Pierwsze dotknięcie ekranu wyłącza IDLE
- IDLE wraca po 60s braku aktywności

---

## ⚡ Nowe Urządzenie - Plug-and-Play

### Automatyczna instalacja terminala + drukarki

```bash
# Na nowym urządzeniu (np. admin2) z terminalem Ingenico i drukarką Hwasung:
wget https://raw.githubusercontent.com/.../install-full-device-FIXED.sh
sudo bash install-full-device-FIXED.sh cashier
sudo reboot

# Po reboot - wszystko działa automatycznie! ✅
# - Terminal płatniczy wykryty
# - Drukarka wykryta
# - CARD payment option widoczny
# - Bez żadnej konfiguracji na serwerze!
```

**Jak to działa:**
1. Skrypt wykrywa sprzęt (terminal + drukarka)
2. Instaluje serwisy z heartbeat (deviceId = hostname)
3. Konfiguruje chromium z parametrem `?deviceId=$(hostname)`
4. Device-manager automatycznie rejestruje urządzenie przez heartbeat
5. Frontend automatycznie wykrywa capabilities
6. **Gotowe!** Brak ręcznej konfiguracji.

---

## 🚀 Quick Start

### Sprawdzanie Statusu

```bash
# Device Manager
curl http://192.168.31.139:8090/devices

# Backend Health
curl http://192.168.31.139:3000/health

# Payment Terminal (admin1)
ssh admin1@192.168.31.205
curl http://localhost:8082/health
```

### Restartowanie Serwisów

```bash
# Na admin1
sudo systemctl restart payment-terminal
sudo systemctl restart printer-service

# Na kiosk-server
docker restart gastro_backend
docker restart gastro_device_manager
```

---

## 📍 Architektura Sieciowa

### Serwery

| Urządzenie | Local IP | VPN IP | Funkcja |
|------------|----------|--------|---------|
| **kiosk-server** | 192.168.31.139 | 100.64.0.7 | Backend, device-manager, nginx |
| **kiosk** | 192.168.31.35 | - | **Cashier Admin Panel** (:3003) |
| **admin1** | 192.168.31.205 | 100.64.0.6 | **Customer Kiosk** (:3001) + Terminal + Printer |
| **kiosk2** | 192.168.31.170 | - | **Order Status Display** (:3002) |

### Porty

| Port | Serwis | Lokalizacja |
|------|--------|-------------|
| 3000 | Backend API | kiosk-server |
| 8090 | Device Manager | kiosk-server |
| 8082 | Payment Terminal | admin1 |
| 8081 | Printer Service | admin1 |
| 3001 | Frontend (Customer Kiosk) | admin1 → nginx → kiosk-server |
| 3002 | Frontend (Order Display) | kiosk2 → nginx → kiosk-server |
| 3003 | Frontend (Cashier Admin) | kiosk → nginx → kiosk-server |

---

## 🔧 Recent Fix - Payment Terminal (2025-12-19)

### Problem
"Płatność nie powiodła się" - terminal płatniczy nie działał (wcześniej działał)

### Przyczyna
Zmiana IP serwera kiosk-server z `100.64.0.4` na `100.64.0.7` (Headscale VPN)

### Rozwiązanie
1. ✅ Zaktualizowano IP w heartbeat services (payment-terminal + printer)
2. ✅ Naprawiono merge logic w device-manager
3. ✅ Backend API odpytuje device-manager dynamicznie
4. ✅ Utworzono printer systemd service

**Status**: ✅ Naprawione - system działa poprawnie

📄 **Szczegóły**: `PAYMENT_TERMINAL_FIXED_FINAL.md`

---

## 📚 Dokumentacja

### Główne Dokumenty
- `DOCS/FULL_DOCUMENTATION.md` - Pełna dokumentacja techniczna
- `PAYMENT_TERMINAL_FIXED_FINAL.md` - Raport naprawy terminala płatniczego
- `CHANGELOG.md` - Historia zmian (wersja 3.0.4)
- `VERIFICATION_REPORT.md` - Raport weryfikacji

### Archiwum
- `archive/` - Stare raporty i dokumentacja historyczna

---

## 🛠️ Maintenance

### Sprawdzanie Logów

```bash
# Backend
docker logs gastro_backend --tail 50

# Device Manager
docker logs gastro_device_manager --tail 50

# Payment Terminal (admin1)
tail -f /home/admin1/payment-terminal-service/logs/payment-terminal.log

# Printer (admin1)
tail -f /home/admin1/printer-service/logs/service.log
```

### Restart Po Zmianach

```bash
# Admin1 - systemd services
sudo systemctl daemon-reload
sudo systemctl restart payment-terminal
sudo systemctl restart printer-service

# Kiosk-server - Docker
docker restart gastro_backend
docker restart gastro_device_manager
```

---

## 🧪 Testing

### Test Device Capabilities

```bash
curl -s 'http://192.168.31.139:3000/api/devices/capabilities' \
  -H 'x-device-id: admin1-RB102' | jq .
```

Expected:
```json
{
  "hasTerminal": true,
  "hasPrinter": true,
  "terminalUrl": "http://100.64.0.6:8082",
  "printerUrl": "http://100.64.0.6:8081"
}
```

### Test Payment Terminal

```bash
curl -X POST http://192.168.31.205:8082/payment/start \
  -H 'Content-Type: application/json' \
  -d '{
    "orderId": "test-123",
    "amount": 1.00,
    "description": "Test",
    "operatorCode": "0001"
  }'
```

---

## 🔒 Credentials

### SSH Access
- **kiosk-server**: `kiosk-server@192.168.31.139` (hasło: 1234)
- **admin1**: `admin1@192.168.31.205` (hasło: 12345)

### Terminal
- **TID**: 01100460
- **IP**: 10.42.0.75
- **Protocol**: PeP (Polskie ePłatności)

---

## 📞 Support

### Polskie ePłatności
- Terminal TID: **01100460**
- W przypadku problemów z autoryzacją płatności

### Kod Błędu 02
Jeśli terminal zwraca kod 02 ("Transaction rejected - other"):
1. Sprawdź tryb pracy terminala (Menu > Konfiguracja)
2. Zweryfikuj aktywację u operatora
3. Test z prawdziwą kartą płatniczą (nie testową)

---

## 🎯 System Status

| Komponent | Status | Uwagi |
|-----------|--------|-------|
| Backend API | ✅ Running | Port 3000, healthy |
| Device Manager | ✅ Running | Port 8090, merge logic fixed |
| Payment Terminal | ✅ Running | Bound to 10.42.0.75 |
| Printer Service | ✅ Running | Port 8081 |
| Heartbeat Services | ✅ Running | Both active, 30s interval |
| Frontend | ✅ Running | All ports accessible |

---

## 📝 Version History

- **3.0.4** (2025-12-19) - Fixed payment terminal IP issue
- **3.0.3** (2025-12-19) - Added heartbeat services
- **3.0.2** - Device discovery improvements
- **3.0.1** - Initial production deployment

---

**Maintained by**: Rovo Dev AI Agent  
**Last Updated**: 2025-12-19 17:55 CET

---

## ✅ LATEST UPDATE (v3.1.0) - ENTERPRISE INSTALLATION SYSTEM

**2025-12-22**: Complete rewrite of installation system for enterprise deployments

### What's New in v3.1.0

**New Installation Script**: `scripts/kiosk-install-v2.sh`
- Eliminates autostart conflicts (single systemd service)
- Proper display manager configuration (LightDM + auto-login)
- Touch-screen optimized with full validation
- Enterprise-grade error handling and logging
- 8 installation phases with automated health checks

**Complete Documentation Suite**:
- DEPLOYMENT_INSTRUCTIONS.md - 30-page step-by-step guide
- PRE_FLIGHT_CHECKLIST.md - Field technician checklist
- TROUBLESHOOTING_GUIDE.md - 25 pages of solutions
- VALIDATION_TEST_PROCEDURE.md - 10 comprehensive test suites
- RAPORT_AUTOSTART_ANALYSIS.md - Technical deep-dive

**Ready for production**: Multi-location deployments with Headscale VPN

---

## PREVIOUS UPDATES

### v3.0.7

**All Systems Operational!**

Dzisiejsze naprawy (2025-12-19):
- ✅ **WebSocket** - Display i Cashier używają nginx proxy, brak błędów
- ✅ **Chromium** - tylko jedna instancja, czysty profil przy każdym starcie
- ✅ **Klawiatura ekranowa** - Onboard zainstalowany, automatyczne pokazywanie
- ✅ **Plug-and-play** - nowe urządzenia automatycznie wykrywane
- ✅ **Cache** - wyczyszczony, brak przywracania sesji

**Backup stabilnej konfiguracji**: `backup_working_20251219_175427.tar.gz`  
**Production Environment**: Gastro Kiosk Pro
