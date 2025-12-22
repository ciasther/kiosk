# Manual Installation Guide - LightDM + Systemd Method

**Wersja**: 3.1.0  
**Metoda**: LightDM + Openbox + Systemd Service  
**Dla**: Ubuntu 22.04 / 24.04 LTS  
**Czas**: 30-40 minut  

Ten dokument pokazuje **ręczną instalację** systemu kiosk - każdy krok po kolei.

**Uwaga**: Jeśli wolisz automatyczną instalację, użyj: `sudo bash kiosk-install-v2.sh`

---

## PRZED ROZPOCZĘCIEM

### Co będzie potrzebne:

1. Świeża instalacja Ubuntu 22.04 lub 24.04 LTS
2. Połączenie internetowe (Ethernet zalecane)
3. Dostęp root (sudo)
4. Authkey z serwera Headscale
5. 30-40 minut czasu

### Przygotowanie zmiennych (DOSTOSUJ DO SIEBIE):

```bash
# ZMIEŃ TE WARTOŚCI!
export DEVICE_HOSTNAME="kiosk01"          # Nazwa urządzenia
export DEVICE_USER="kiosk"                # Nazwa użytkownika
export SERVER_IP="100.64.0.7"             # IP serwera w VPN
export SERVER_PORT="3001"                 # Port aplikacji (3001=customer, 3003=cashier, 3002=display)
export DEVICE_MANAGER_URL="http://100.64.0.7:8090"
export HEADSCALE_SERVER="https://headscale.your-domain.com"
export AUTHKEY="YOUR_AUTHKEY_HERE"        # Wygeneruj: headscale preauthkeys create --expiration 24h
```

Skopiuj powyższe komendy do terminala i dostosuj wartości.

---

## CZĘŚĆ 1: PODSTAWOWY SYSTEM

### Krok 1.1: Aktualizacja systemu

```bash
sudo apt update
sudo apt upgrade -y
```

**Czas**: 2-5 minut

---

### Krok 1.2: Ustawienie hostname

```bash
sudo hostnamectl set-hostname "$DEVICE_HOSTNAME"

# Sprawdź
hostname
# Powinno pokazać: kiosk01 (lub Twoja nazwa)
```

---

### Krok 1.3: Instalacja podstawowych narzędzi

```bash
sudo apt install -y \
    curl \
    wget \
    git \
    htop \
    net-tools \
    ssh \
    vim \
    unzip \
    ca-certificates \
    gnupg \
    lsb-release \
    software-properties-common
```

**Czas**: 1-2 minuty

---

### Krok 1.4: Utworzenie użytkownika kiosk

```bash
# Utwórz użytkownika
sudo useradd -m -s /bin/bash "$DEVICE_USER"

# Ustaw hasło
echo "$DEVICE_USER:gastro2024" | sudo chpasswd

# Dodaj do grupy sudo
sudo usermod -aG sudo "$DEVICE_USER"

# Sprawdź
id $DEVICE_USER
# Powinno pokazać: uid=...(kiosk) gid=...(kiosk) groups=...,sudo
```

---

## CZĘŚĆ 2: DISPLAY MANAGER I GUI

### Krok 2.1: Instalacja LightDM

```bash
sudo DEBIAN_FRONTEND=noninteractive apt install -y \
    xorg \
    lightdm \
    lightdm-gtk-greeter \
    lightdm-gtk-greeter-settings
```

**Czas**: 3-5 minut

**Uwaga**: Jeśli zapyta o wybór display managera, wybierz **lightdm**

---

### Krok 2.2: Instalacja Openbox

```bash
sudo apt install -y \
    openbox \
    obconf \
    obmenu \
    tint2 \
    nitrogen
```

**Czas**: 1-2 minuty

---

### Krok 2.3: Konfiguracja auto-login

```bash
# Utwórz plik konfiguracyjny
sudo mkdir -p /etc/lightdm/lightdm.conf.d/

sudo bash -c "cat > /etc/lightdm/lightdm.conf.d/50-autologin.conf" <<EOF
[Seat:*]
autologin-user=$DEVICE_USER
autologin-user-timeout=0
user-session=openbox
EOF

# Sprawdź
cat /etc/lightdm/lightdm.conf.d/50-autologin.conf
```

**Co to robi**: Automatyczne logowanie jako użytkownik kiosk przy starcie.

---

### Krok 2.4: Ustaw LightDM jako domyślny display manager

```bash
sudo bash -c "echo '/usr/sbin/lightdm' > /etc/X11/default-display-manager"

sudo DEBIAN_FRONTEND=noninteractive dpkg-reconfigure lightdm
```

---

### Krok 2.5: Konfiguracja Openbox autostart

```bash
# Utwórz katalog
sudo -u $DEVICE_USER mkdir -p /home/$DEVICE_USER/.config/openbox

# Utwórz plik autostart (TYLKO system settings, NIE chromium!)
sudo -u $DEVICE_USER bash -c "cat > /home/$DEVICE_USER/.config/openbox/autostart" <<'EOF'
# Wyłącz wygaszacz ekranu
xset s off
xset -dpms
xset s noblank

# Ukryj kursor po 0.1s braku aktywności
unclutter -idle 0.1 -root &

# Wyłącz screensaver (jeśli zainstalowany)
xscreensaver-command -exit 2>/dev/null || true

# UWAGA: Chromium NIE jest tutaj!
# Jest uruchamiany przez systemd service (gastro-kiosk.service)
EOF

# Sprawdź
cat /home/$DEVICE_USER/.config/openbox/autostart
```

---

### Krok 2.6: Wyłączenie screen lock

```bash
sudo -u $DEVICE_USER mkdir -p /home/$DEVICE_USER/.config/autostart

sudo -u $DEVICE_USER bash -c "cat > /home/$DEVICE_USER/.config/autostart/disable-screensaver.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Disable Screensaver
Exec=xset s off -dpms s noblank
EOF
```

---

## CZĘŚĆ 3: CHROMIUM BROWSER

### Krok 3.1: Instalacja Chromium

```bash
sudo apt install -y \
    chromium-browser \
    chromium-browser-l10n \
    chromium-codecs-ffmpeg
```

**Czas**: 2-3 minuty

---

### Krok 3.2: Instalacja wsparcia dla ekranów dotykowych

```bash
sudo apt install -y \
    xserver-xorg-input-evdev \
    xinput \
    xinput-calibrator
```

---

### Krok 3.3: Instalacja unclutter (ukrywanie kursora)

```bash
sudo apt install -y unclutter
```

---

## CZĘŚĆ 4: VPN (TAILSCALE/HEADSCALE)

### Krok 4.1: Instalacja Tailscale

```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

**Czas**: 1-2 minuty

---

### Krok 4.2: Połączenie z Headscale

```bash
# Zatrzymaj tailscale (jeśli działa)
sudo systemctl stop tailscaled

# Połącz z authkey
sudo tailscale up \
    --login-server="$HEADSCALE_SERVER" \
    --authkey="$AUTHKEY" \
    --hostname="$DEVICE_HOSTNAME" \
    --accept-routes \
    --accept-dns=false
```

---

### Krok 4.3: Weryfikacja połączenia VPN

```bash
# Sprawdź status
sudo tailscale status

# Powinno pokazać serwer
sudo tailscale status | grep "$SERVER_IP"

# Przykładowy output:
# 100.64.0.7    kiosk-server    tagged-devices   online
```

**Jeśli NIE pokazuje serwera**: Problem z authkey lub Headscale server.

---

### Krok 4.4: Włączenie autostart Tailscale

```bash
sudo systemctl enable tailscaled
```

---

## CZĘŚĆ 5: KIOSK SERVICE (NAJWAŻNIEJSZA CZĘŚĆ!)

To jest serce systemu - systemd service który uruchamia aplikację.

---

### Krok 5.1: Utworzenie startup script

```bash
# Utwórz plik
sudo nano /usr/local/bin/gastro-kiosk-start.sh
```

**Wklej poniższą zawartość** (Ctrl+Shift+V):

```bash
#!/bin/bash
################################################################################
# Gastro Kiosk Startup Script
################################################################################

LOG_FILE="/var/log/gastro-kiosk-startup.log"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log "========================================="
log "Gastro Kiosk startup initiated"
log "========================================="

# Pobierz konfigurację z environment (ustawione przez systemd)
SERVER_IP="${SERVER_IP:-100.64.0.7}"
SERVER_PORT="${SERVER_PORT:-3001}"
DEVICE_HOSTNAME="${DEVICE_HOSTNAME:-$(hostname)}"

log "Configuration:"
log "  Server: $SERVER_IP:$SERVER_PORT"
log "  Device: $DEVICE_HOSTNAME"
log "  Display: $DISPLAY"
log "  User: $USER"

# FAZA 1: Czekaj na X11 server
log "Waiting for X11 server..."
for i in {1..60}; do
    if xset q &>/dev/null; then
        log "X11 server is ready!"
        break
    fi
    sleep 1
    if [[ $i -eq 60 ]]; then
        log "ERROR: X11 server timeout"
        exit 1
    fi
done

# FAZA 2: Czekaj na VPN
log "Waiting for VPN connection..."
for i in {1..60}; do
    if tailscale status | grep -q "$SERVER_IP"; then
        log "VPN connected!"
        tailscale status | grep "$SERVER_IP" | tee -a "$LOG_FILE"
        break
    fi
    sleep 2
    if [[ $i -eq 60 ]]; then
        log "WARNING: VPN connection timeout. Continuing anyway..."
        break
    fi
done

# FAZA 3: Test connectivity do serwera
log "Testing connectivity to server..."
for i in {1..30}; do
    if curl -k -s -o /dev/null -w "%{http_code}" "https://$SERVER_IP:$SERVER_PORT" | grep -q "200\|301\|302"; then
        log "Server is reachable!"
        break
    fi
    sleep 2
    if [[ $i -eq 30 ]]; then
        log "WARNING: Cannot reach server. Continuing anyway..."
        break
    fi
done

# FAZA 4: Ustawienia X11
log "Applying X11 settings..."
xset s off          # Wyłącz screensaver
xset -dpms          # Wyłącz power management
xset s noblank      # Zapobiegnij blanking

# FAZA 5: Ukryj kursor
log "Starting unclutter (cursor hiding)..."
unclutter -idle 0.1 -root &

# FAZA 6: Wyczyść stare procesy chromium
log "Cleaning up old Chromium processes..."
pkill -f "chromium.*$SERVER_PORT" || true
sleep 2

# FAZA 7: Utwórz tymczasowy profil
CHROME_PROFILE="/tmp/chromium-kiosk-$$"
mkdir -p "$CHROME_PROFILE"
log "Chromium profile: $CHROME_PROFILE"

# FAZA 8: Zbuduj URL z deviceId
URL="https://${SERVER_IP}:${SERVER_PORT}?deviceId=${DEVICE_HOSTNAME}"
log "Application URL: $URL"

# FAZA 9: Uruchom Chromium
log "Launching Chromium browser..."
exec chromium-browser \
    --kiosk \
    --no-first-run \
    --disable-infobars \
    --disable-features=TranslateUI \
    --disable-translate \
    --disable-session-crashed-bubble \
    --disable-component-update \
    --noerrdialogs \
    --disable-logging \
    --disable-login-animations \
    --disable-notifications \
    --disable-pinch \
    --overscroll-history-navigation=0 \
    --disable-sync \
    --disable-restore-session-state \
    --disable-save-password-bubble \
    --ignore-certificate-errors \
    --check-for-update-interval=31536000 \
    --touch-events=enabled \
    --user-data-dir="$CHROME_PROFILE" \
    "$URL" \
    >> "$LOG_FILE" 2>&1
```

**Zapisz**: Ctrl+X, Y, Enter

---

### Krok 5.2: Nadaj uprawnienia wykonywania

```bash
sudo chmod +x /usr/local/bin/gastro-kiosk-start.sh

# Sprawdź
ls -l /usr/local/bin/gastro-kiosk-start.sh
# Powinno pokazać: -rwxr-xr-x (executable)
```

---

### Krok 5.3: Utworzenie systemd service

```bash
# Utwórz plik service
sudo nano /etc/systemd/system/gastro-kiosk.service
```

**Wklej poniższą zawartość**:

```ini
[Unit]
Description=Gastro Kiosk Application
After=graphical.target network-online.target tailscaled.service
Wants=network-online.target
Requires=tailscaled.service

[Service]
Type=simple
User=kiosk
Environment="DISPLAY=:0"
Environment="XAUTHORITY=/home/kiosk/.Xauthority"
Environment="SERVER_IP=100.64.0.7"
Environment="SERVER_PORT=3001"
Environment="DEVICE_HOSTNAME=kiosk01"
ExecStart=/usr/local/bin/gastro-kiosk-start.sh
Restart=always
RestartSec=10
StandardOutput=append:/var/log/gastro-kiosk.log
StandardError=append:/var/log/gastro-kiosk.log

[Install]
WantedBy=graphical.target
```

**WAŻNE**: Dostosuj wartości Environment do swoich ustawień:
- `User=` → Twoja nazwa użytkownika (np. kiosk)
- `XAUTHORITY=` → Ścieżka do .Xauthority użytkownika
- `SERVER_IP=` → IP serwera w VPN
- `SERVER_PORT=` → Port aplikacji (3001/3002/3003)
- `DEVICE_HOSTNAME=` → Hostname urządzenia

**Zapisz**: Ctrl+X, Y, Enter

---

### Krok 5.4: Reload systemd i włącz service

```bash
# Reload daemon (odczytaj nowy service)
sudo systemctl daemon-reload

# Włącz autostart
sudo systemctl enable gastro-kiosk.service

# Sprawdź status (nie uruchamiaj jeszcze!)
systemctl status gastro-kiosk.service
# Powinno pokazać: "loaded" (nie "active" - to normalne przed rebootem)
```

---

## CZĘŚĆ 6: HEARTBEAT SERVICES (OPCJONALNIE)

**Ta sekcja tylko dla urządzeń z drukarką lub terminalem płatniczym!**

Jeśli NIE masz drukarki/terminala - **pomiń tę część**.

---

### Krok 6.1: Instalacja Node.js

```bash
# Dodaj repozytorium Node.js 20.x
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo bash -

# Zainstaluj Node.js
sudo apt install -y nodejs

# Sprawdź wersję
node --version
# Powinno pokazać: v20.x.x

npm --version
# Powinno pokazać: 10.x.x
```

**Czas**: 2-3 minuty

---

### Krok 6.2A: Instalacja Printer Service (jeśli masz drukarkę)

```bash
# Utwórz katalog
sudo -u $DEVICE_USER mkdir -p /home/$DEVICE_USER/printer-service
cd /home/$DEVICE_USER/printer-service

# Utwórz server.js
sudo -u $DEVICE_USER bash -c 'cat > server.js' <<'NODE_EOF'
const http = require('http');
const { exec } = require('child_process');
const axios = require('axios');

const PORT = process.env.PORT || 8083;
const DEVICE_ID = process.env.DEVICE_ID || require('os').hostname();
const DEVICE_MANAGER_URL = process.env.DEVICE_MANAGER_URL || 'http://100.64.0.7:8090';

// Heartbeat do device managera co 30s
setInterval(() => {
    axios.post(`${DEVICE_MANAGER_URL}/register`, {
        deviceId: DEVICE_ID,
        capabilities: { printer: true },
        timestamp: Date.now()
    }).catch(err => console.error('Heartbeat failed:', err.message));
}, 30000);

// Health endpoint
const server = http.createServer((req, res) => {
    if (req.url === '/health') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ status: 'ok', deviceId: DEVICE_ID }));
    } else if (req.url === '/print' && req.method === 'POST') {
        let body = '';
        req.on('data', chunk => body += chunk);
        req.on('end', () => {
            const data = JSON.parse(body);
            console.log('Print request:', data);
            // TODO: Implementacja drukowania (escpos, etc.)
            res.writeHead(200);
            res.end(JSON.stringify({ success: true }));
        });
    }
});

server.listen(PORT, () => {
    console.log(`Printer service listening on port ${PORT}`);
    console.log(`Device ID: ${DEVICE_ID}`);
    console.log(`Device Manager: ${DEVICE_MANAGER_URL}`);
});
NODE_EOF

# Utwórz package.json
sudo -u $DEVICE_USER bash -c 'cat > package.json' <<'JSON_EOF'
{
  "name": "printer-service",
  "version": "1.0.0",
  "main": "server.js",
  "dependencies": {
    "axios": "^1.6.0"
  }
}
JSON_EOF

# Zainstaluj dependencies
sudo -u $DEVICE_USER npm install

# Utwórz systemd service
sudo bash -c "cat > /etc/systemd/system/gastro-printer.service" <<EOF
[Unit]
Description=Gastro Printer Service
After=network.target

[Service]
Type=simple
User=$DEVICE_USER
WorkingDirectory=/home/$DEVICE_USER/printer-service
Environment="PORT=8083"
Environment="DEVICE_ID=$DEVICE_HOSTNAME"
Environment="DEVICE_MANAGER_URL=$DEVICE_MANAGER_URL"
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Włącz i uruchom
sudo systemctl daemon-reload
sudo systemctl enable gastro-printer.service
sudo systemctl start gastro-printer.service

# Sprawdź status
systemctl status gastro-printer.service
```

---

### Krok 6.2B: Instalacja Terminal Service (jeśli masz terminal płatniczy)

```bash
# Utwórz katalog
sudo -u $DEVICE_USER mkdir -p /home/$DEVICE_USER/payment-terminal-service
cd /home/$DEVICE_USER/payment-terminal-service

# Utwórz server.js
sudo -u $DEVICE_USER bash -c 'cat > server.js' <<'NODE_EOF'
const http = require('http');
const axios = require('axios');

const PORT = process.env.PORT || 8082;
const DEVICE_ID = process.env.DEVICE_ID || require('os').hostname();
const DEVICE_MANAGER_URL = process.env.DEVICE_MANAGER_URL || 'http://100.64.0.7:8090';

// Heartbeat do device managera co 30s
setInterval(() => {
    axios.post(`${DEVICE_MANAGER_URL}/register`, {
        deviceId: DEVICE_ID,
        capabilities: { paymentTerminal: true },
        timestamp: Date.now()
    }).catch(err => console.error('Heartbeat failed:', err.message));
}, 30000);

// Health endpoint
const server = http.createServer((req, res) => {
    if (req.url === '/health') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ status: 'ok', deviceId: DEVICE_ID }));
    }
});

server.listen(PORT, () => {
    console.log(`Payment terminal service listening on port ${PORT}`);
    console.log(`Device ID: ${DEVICE_ID}`);
    console.log(`Device Manager: ${DEVICE_MANAGER_URL}`);
});
NODE_EOF

# Utwórz package.json
sudo -u $DEVICE_USER bash -c 'cat > package.json' <<'JSON_EOF'
{
  "name": "payment-terminal-service",
  "version": "1.0.0",
  "main": "server.js",
  "dependencies": {
    "axios": "^1.6.0"
  }
}
JSON_EOF

# Zainstaluj dependencies
sudo -u $DEVICE_USER npm install

# Utwórz systemd service
sudo bash -c "cat > /etc/systemd/system/gastro-terminal.service" <<EOF
[Unit]
Description=Gastro Payment Terminal Service
After=network.target

[Service]
Type=simple
User=$DEVICE_USER
WorkingDirectory=/home/$DEVICE_USER/payment-terminal-service
Environment="PORT=8082"
Environment="DEVICE_ID=$DEVICE_HOSTNAME"
Environment="DEVICE_MANAGER_URL=$DEVICE_MANAGER_URL"
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Włącz i uruchom
sudo systemctl daemon-reload
sudo systemctl enable gastro-terminal.service
sudo systemctl start gastro-terminal.service

# Sprawdź status
systemctl status gastro-terminal.service
```

---

## CZĘŚĆ 7: CLEANUP I ZABEZPIECZENIA

### Krok 7.1: Wyłączenie konfliktujących autostartów

```bash
# Wyłącz XDG autostart chromium (jeśli istnieje)
if [ -f "/home/$DEVICE_USER/.config/autostart/chromium.desktop" ]; then
    sudo -u $DEVICE_USER mv "/home/$DEVICE_USER/.config/autostart/chromium.desktop" \
       "/home/$DEVICE_USER/.config/autostart/chromium.desktop.disabled"
    echo "Disabled XDG chromium autostart"
fi

# Wyłącz stare kiosk services (jeśli istnieją)
for service in kiosk-frontend bakery-kiosk-browser kiosk-browser; do
    if systemctl list-unit-files | grep -q "$service.service"; then
        sudo systemctl disable "$service.service" 2>/dev/null || true
        echo "Disabled old service: $service.service"
    fi
done
```

---

### Krok 7.2: Uprawnienia

```bash
# Upewnij się że wszystkie pliki należą do użytkownika
sudo chown -R $DEVICE_USER:$DEVICE_USER /home/$DEVICE_USER
```

---

### Krok 7.3: Czyszczenie apt cache

```bash
sudo apt autoremove -y
sudo apt clean
```

---

## CZĘŚĆ 8: WALIDACJA

Przed rebootem sprawdźmy czy wszystko jest OK.

---

### Krok 8.1: Sprawdź użytkownika

```bash
id $DEVICE_USER
# Powinno pokazać: uid, gid, groups (z sudo)
```

---

### Krok 8.2: Sprawdź LightDM

```bash
systemctl is-enabled lightdm
# Powinno pokazać: enabled
```

---

### Krok 8.3: Sprawdź Chromium

```bash
chromium-browser --version
# Powinno pokazać: Chromium XX.X.XXXX.XX
```

---

### Krok 8.4: Sprawdź VPN

```bash
sudo tailscale status | grep "$SERVER_IP"
# Powinno pokazać: 100.64.0.7 ... online
```

---

### Krok 8.5: Sprawdź kiosk service

```bash
systemctl is-enabled gastro-kiosk.service
# Powinno pokazać: enabled

ls -l /usr/local/bin/gastro-kiosk-start.sh
# Powinno pokazać: -rwxr-xr-x (executable)
```

---

### Krok 8.6: Sprawdź heartbeat services (jeśli zainstalowane)

```bash
# Drukarka
systemctl status gastro-printer.service

# Terminal
systemctl status gastro-terminal.service
```

---

## CZĘŚĆ 9: REBOOT I WERYFIKACJA

### Krok 9.1: Reboot

```bash
echo "=== INSTALLATION COMPLETE ==="
echo ""
echo "Services status:"
systemctl is-enabled lightdm
systemctl is-enabled gastro-kiosk.service
echo ""
echo "Ready to reboot!"
echo ""
read -p "Reboot now? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo reboot
fi
```

---

### Krok 9.2: Po restarcie - Sprawdź

Po restarcie urządzenie powinno:

1. **Auto-login** (bez ekranu logowania)
2. **Openbox** uruchomiony (lekkie środowisko)
3. **Chromium** otwiera się automatycznie w fullscreen
4. **Aplikacja** załadowana (ekran IDLE lub menu)

**Jeśli coś nie działa**, sprawdź logi:

```bash
# SSH do urządzenia (z innego komputera)
ssh kiosk@<IP_URZADZENIA>

# Sprawdź logi startowe
cat /var/log/gastro-kiosk-startup.log

# Sprawdź logi service
journalctl -u gastro-kiosk.service -n 50

# Sprawdź status
systemctl status gastro-kiosk.service
```

---

## CZĘŚĆ 10: TROUBLESHOOTING

### Problem: Czarny ekran po restarcie

```bash
# Przełącz na TTY: Ctrl+Alt+F2
# Zaloguj jako kiosk

# Sprawdź LightDM
sudo systemctl status lightdm

# Jeśli inactive - uruchom
sudo systemctl start lightdm

# Wróć do GUI: Ctrl+Alt+F7
```

---

### Problem: Aplikacja się nie uruchomiła

```bash
# SSH do urządzenia
ssh kiosk@<IP>

# Sprawdź service
systemctl status gastro-kiosk.service

# Sprawdź logi
journalctl -u gastro-kiosk.service -n 50

# Ręcznie uruchom (do testów)
sudo systemctl start gastro-kiosk.service
```

---

### Problem: VPN nie połączony

```bash
# Sprawdź status
sudo tailscale status

# Jeśli nie połączony
sudo tailscale down
sudo tailscale up \
    --login-server="$HEADSCALE_SERVER" \
    --authkey="NOWY_AUTHKEY" \
    --hostname="$DEVICE_HOSTNAME" \
    --accept-routes

# Restart kiosk service
sudo systemctl restart gastro-kiosk.service
```

---

## MANAGEMENT - CODZIENNE UŻYCIE

### Restart aplikacji (bez pełnego rebootu)

```bash
sudo systemctl restart gastro-kiosk.service
```

---

### Sprawdzenie statusu

```bash
systemctl status gastro-kiosk.service
```

---

### Logi live (real-time)

```bash
journalctl -u gastro-kiosk.service -f
```

---

### Wyłączenie aplikacji (maintenance mode)

```bash
sudo systemctl stop gastro-kiosk.service
```

---

### Ponowne włączenie

```bash
sudo systemctl start gastro-kiosk.service
```

---

### Sprawdzenie VPN

```bash
sudo tailscale status
```

---

### Sprawdzenie heartbeat (device-manager)

```bash
# Z urządzenia kiosk
curl http://100.64.0.7:8090/devices/$(hostname)

# Powinno zwrócić JSON z capabilities
```

---

## PODSUMOWANIE

### Co zostało zainstalowane:

1. ✅ **LightDM** - Display manager z auto-login
2. ✅ **Openbox** - Lekki window manager
3. ✅ **Chromium** - Przeglądarka w kiosk mode
4. ✅ **Tailscale** - VPN client połączony z Headscale
5. ✅ **Systemd service** - gastro-kiosk.service (auto-restart)
6. ✅ **Startup script** - /usr/local/bin/gastro-kiosk-start.sh
7. ✅ **Heartbeat services** - printer/terminal (opcjonalnie)

### Architektura:

```
Boot → LightDM (auto-login kiosk) 
    → Openbox (window manager)
        → Systemd service (gastro-kiosk)
            → Startup script (walidacja: X11, VPN, connectivity)
                → Chromium (kiosk mode, fullscreen)
                    → Aplikacja (https://100.64.0.7:3001?deviceId=kiosk01)
```

### Pliki konfiguracyjne:

- `/etc/lightdm/lightdm.conf.d/50-autologin.conf` - Auto-login config
- `/home/kiosk/.config/openbox/autostart` - System settings (xset, unclutter)
- `/etc/systemd/system/gastro-kiosk.service` - Systemd unit file
- `/usr/local/bin/gastro-kiosk-start.sh` - Startup script (walidacja + chromium)

### Logi:

- `/var/log/gastro-kiosk-startup.log` - Startup script logs
- `/var/log/gastro-kiosk.log` - Service stdout/stderr
- `journalctl -u gastro-kiosk.service` - Systemd logs

---

## NASTĘPNE KROKI

1. **Przetestuj pełny flow zamówienia** (dodaj produkt, checkout, płatność)
2. **Sprawdź czy drukarka/terminal wykryte** (jeśli zainstalowane)
3. **Wykonaj VALIDATION_TEST_PROCEDURE.md** (pełne testy)
4. **Skonfiguruj monitoring** (opcjonalnie - Uptime Kuma, Grafana)

---

**KONIEC INSTRUKCJI RĘCZNEJ**

**Pytania?** Sprawdź: `TROUBLESHOOTING_GUIDE.md`

**Wolisz automatyczną instalację?** Użyj: `sudo bash kiosk-install-v2.sh`