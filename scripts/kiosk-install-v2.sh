#!/bin/bash
################################################################################
# Gastro Kiosk Pro - Production Installation Script v2.0
# 
# Description: Enterprise-grade installation script for kiosk devices
# Features:
#   - Single autostart method (systemd only)
#   - LightDM with auto-login
#   - Touch-screen optimized
#   - Idempotent (can run multiple times safely)
#   - Full validation and error handling
#   - Headscale/Tailscale VPN integration
#
# Requirements:
#   - Fresh Ubuntu 22.04 LTS or 24.04 LTS
#   - Internet connection
#   - sudo privileges
#
# Usage:
#   sudo bash kiosk-install-v2.sh
#
# Version: 2.0.0
# Date: 2025-12-22
################################################################################

set -u  # Exit on undefined variable
# NOTE: Removed 'set -e' to allow graceful error handling

################################################################################
# CONFIGURATION
################################################################################

# Server configuration
readonly SERVER_IP="100.64.0.7"
SERVER_PORT="3001"  # Not readonly - will be set based on device role
readonly DEVICE_MANAGER_URL="http://${SERVER_IP}:8090"
readonly BACKEND_URL="https://${SERVER_IP}:3000"

# Headscale/Tailscale configuration
readonly HEADSCALE_SERVER="https://headscale.your-domain.com"
readonly AUTHKEY_PLACEHOLDER="YOUR_AUTHKEY_HERE"

# Device configuration
DEVICE_ROLE="customer"  # customer, cashier, display
DEVICE_USER=""
DEVICE_HOSTNAME=""

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Log file
readonly LOG_FILE="/var/log/gastro-kiosk-install.log"

################################################################################
# HELPER FUNCTIONS
################################################################################

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*" | tee -a "$LOG_FILE" >&2
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $*" | tee -a "$LOG_FILE"
}

print_header() {
    echo ""
    echo "================================================================================"
    echo "  $1"
    echo "================================================================================"
    echo ""
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_ubuntu() {
    if ! grep -q "Ubuntu" /etc/os-release; then
        log_error "This script is designed for Ubuntu. Detected: $(cat /etc/os-release | grep PRETTY_NAME)"
        exit 1
    fi
    
    local version=$(grep VERSION_ID /etc/os-release | cut -d'"' -f2)
    log_info "Detected Ubuntu version: $version"
    
    if [[ ! "$version" =~ ^(22\.04|24\.04) ]]; then
        log_warning "This script is tested on Ubuntu 22.04 and 24.04. Current: $version"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

prompt_configuration() {
    print_header "DEVICE CONFIGURATION"
    
    # Device role
    echo "Select device role:"
    echo "  1) Customer Kiosk (self-service ordering, port 3001)"
    echo "  2) Cashier Admin (order management, port 3003)"
    echo "  3) Display (status screen, port 3002)"
    read -p "Enter choice [1-3]: " role_choice
    
    case $role_choice in
        1) DEVICE_ROLE="customer"; SERVER_PORT="3001" ;;
        2) DEVICE_ROLE="cashier"; SERVER_PORT="3003" ;;
        3) DEVICE_ROLE="display"; SERVER_PORT="3002" ;;
        *) log_error "Invalid choice"; exit 1 ;;
    esac
    
    # Hostname (auto-generate if empty)
    DEFAULT_HOSTNAME="kiosk-$(date +%s | tail -c 5)"
    read -p "Enter device hostname [${DEFAULT_HOSTNAME}]: " DEVICE_HOSTNAME
    DEVICE_HOSTNAME=${DEVICE_HOSTNAME:-$DEFAULT_HOSTNAME}
    log_info "Using hostname: $DEVICE_HOSTNAME"
    
    # Username (default: kiosk)
    read -p "Enter username for auto-login [kiosk]: " DEVICE_USER
    DEVICE_USER=${DEVICE_USER:-kiosk}
    log_info "Using username: $DEVICE_USER"
    
    # Headscale authkey
    echo ""
    log_warning "You need a Headscale authkey. Generate it on your Headscale server:"
    log_warning "  headscale preauthkeys create --expiration 24h --reusable"
    echo ""
    read -p "Enter Headscale authkey: " AUTHKEY
    if [[ -z "$AUTHKEY" ]]; then
        log_error "Authkey cannot be empty"
        exit 1
    fi
    
    # Confirmation
    echo ""
    log_info "Configuration summary:"
    log_info "  Role: $DEVICE_ROLE"
    log_info "  Hostname: $DEVICE_HOSTNAME"
    log_info "  Username: $DEVICE_USER"
    log_info "  URL: https://${SERVER_IP}:${SERVER_PORT}?deviceId=${DEVICE_HOSTNAME}"
    echo ""
    read -p "Proceed with installation? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Installation cancelled by user"
        exit 0
    fi
}

################################################################################
# INSTALLATION PHASES
################################################################################

phase1_system_preparation() {
    print_header "PHASE 1: SYSTEM PREPARATION"
    
    log "Setting hostname to: $DEVICE_HOSTNAME"
    hostnamectl set-hostname "$DEVICE_HOSTNAME" || log_warning "Failed to set hostname, continuing..."
    
    log "Updating package lists..."
    for i in {1..3}; do
        if apt-get update -qq; then
            log "Package lists updated successfully"
            break
        else
            log_warning "apt-get update failed (attempt $i/3). Retrying in 5s..."
            sleep 5
            if [[ $i -eq 3 ]]; then
                log_warning "apt-get update failed after 3 attempts. Continuing anyway..."
            fi
        fi
    done
    
    log "Installing base utilities..."
    apt-get install -y -qq \
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
        software-properties-common || {
            log_warning "Some packages failed to install. Trying essential ones only..."
            apt-get install -y -qq curl wget ca-certificates || log_error "Critical: Cannot install essential packages"
        }
    
    log "Creating user: $DEVICE_USER"
    if ! id "$DEVICE_USER" &>/dev/null; then
        if useradd -m -s /bin/bash "$DEVICE_USER"; then
            echo "$DEVICE_USER:gastro2024" | chpasswd
            usermod -aG sudo "$DEVICE_USER"
            log "User $DEVICE_USER created with password: gastro2024"
        else
            log_error "Failed to create user $DEVICE_USER"
            exit 1
        fi
    else
        log_info "User $DEVICE_USER already exists"
    fi
    
    log "Phase 1 completed successfully"
}

phase2_display_manager() {
    print_header "PHASE 2: DISPLAY MANAGER & GUI"
    
    log "Installing LightDM display manager..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        xorg \
        lightdm \
        lightdm-gtk-greeter \
        lightdm-gtk-greeter-settings || {
            log_warning "LightDM installation failed. Trying without greeter settings..."
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq xorg lightdm lightdm-gtk-greeter || {
                log_error "Critical: Cannot install display manager"
                exit 1
            }
        }
    
    log "Installing Openbox window manager..."
    apt-get install -y -qq \
        openbox \
        obconf \
        obmenu \
        tint2 \
        nitrogen || {
            log_warning "Some Openbox packages failed. Installing minimal setup..."
            apt-get install -y -qq openbox || {
                log_error "Critical: Cannot install Openbox"
                exit 1
            }
        }
    
    log "Configuring LightDM for auto-login..."
    cat > /etc/lightdm/lightdm.conf.d/50-autologin.conf <<EOF
[Seat:*]
autologin-user=$DEVICE_USER
autologin-user-timeout=0
user-session=openbox
EOF
    
    log "Setting LightDM as default display manager..."
    echo "/usr/sbin/lightdm" > /etc/X11/default-display-manager
    DEBIAN_FRONTEND=noninteractive dpkg-reconfigure lightdm
    
    log "Configuring Openbox for $DEVICE_USER..."
    mkdir -p /home/$DEVICE_USER/.config/openbox
    cat > /home/$DEVICE_USER/.config/openbox/autostart <<'EOF'
# Disable screen blanking
xset s off
xset -dpms
xset s noblank

# Hide cursor after 0.1s of inactivity
unclutter -idle 0.1 -root &

# Disable screen saver
xscreensaver-command -exit 2>/dev/null || true

# Note: Chromium is started by systemd service (gastro-kiosk.service)
# DO NOT add chromium here to avoid conflicts!
EOF
    
    chown -R $DEVICE_USER:$DEVICE_USER /home/$DEVICE_USER/.config
    
    log "Disabling screen lock and power management..."
    mkdir -p /home/$DEVICE_USER/.config/autostart
    cat > /home/$DEVICE_USER/.config/autostart/disable-screensaver.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Disable Screensaver
Exec=xset s off -dpms s noblank
EOF
    
    chown -R $DEVICE_USER:$DEVICE_USER /home/$DEVICE_USER/.config/autostart
    
    log "Phase 2 completed successfully"
}

phase3_chromium() {
    print_header "PHASE 3: CHROMIUM BROWSER"
    
    log "Installing Chromium browser..."
    apt-get install -y -qq \
        chromium-browser \
        chromium-browser-l10n \
        chromium-codecs-ffmpeg || {
            log_warning "Full Chromium install failed. Trying minimal..."
            apt-get install -y -qq chromium-browser || {
                log_error "Critical: Cannot install Chromium"
                exit 1
            }
        }
    
    # Touch screen support
    log "Installing touch screen utilities..."
    apt-get install -y -qq \
        xserver-xorg-input-evdev \
        xinput \
        xinput-calibrator || log_warning "Touch screen utilities installation failed, continuing..."
    
    # Unclutter for hiding cursor
    log "Installing unclutter (cursor hiding)..."
    apt-get install -y -qq unclutter || log_warning "Unclutter installation failed, continuing..."
    
    log "Phase 3 completed successfully"
}

phase4_vpn() {
    print_header "PHASE 4: VPN (TAILSCALE/HEADSCALE)"
    
    log "Installing Tailscale..."
    if ! command -v tailscale &>/dev/null; then
        for i in {1..3}; do
            if curl -fsSL https://tailscale.com/install.sh | sh; then
                log "Tailscale installed successfully"
                break
            else
                log_warning "Tailscale installation failed (attempt $i/3). Retrying..."
                sleep 5
                if [[ $i -eq 3 ]]; then
                    log_error "Critical: Cannot install Tailscale after 3 attempts"
                    exit 1
                fi
            fi
        done
    else
        log_info "Tailscale already installed"
    fi
    
    log "Connecting to Headscale server..."
    log_info "Server: $HEADSCALE_SERVER"
    
    # Stop tailscale if running
    systemctl stop tailscaled 2>/dev/null || true
    sleep 2
    systemctl start tailscaled || log_warning "Failed to start tailscaled"
    sleep 3
    
    # Connect with authkey (with retry)
    for i in {1..3}; do
        if tailscale up \
            --login-server="$HEADSCALE_SERVER" \
            --authkey="$AUTHKEY" \
            --hostname="$DEVICE_HOSTNAME" \
            --accept-routes \
            --accept-dns=false; then
            log "Tailscale up command successful"
            break
        else
            log_warning "Tailscale up failed (attempt $i/3). Retrying..."
            sleep 5
            if [[ $i -eq 3 ]]; then
                log_error "Failed to connect to Headscale. Continuing anyway..."
            fi
        fi
    done
    
    log "Waiting for VPN connection..."
    for i in {1..30}; do
        if tailscale status | grep -q "$SERVER_IP"; then
            log "VPN connected successfully!"
            tailscale status | grep "$SERVER_IP"
            break
        fi
        sleep 2
        if [[ $i -eq 30 ]]; then
            log_warning "VPN connection timeout. Service will retry on boot. Continuing..."
        fi
    done
    
    log "Enabling Tailscale autostart..."
    systemctl enable tailscaled || log_warning "Failed to enable tailscaled, but continuing..."
    
    log "Phase 4 completed successfully"
}

phase5_kiosk_service() {
    print_header "PHASE 5: KIOSK APPLICATION SERVICE"
    
    log "Creating kiosk startup script..."
    cat > /usr/local/bin/gastro-kiosk-start.sh <<'SCRIPT_EOF'
#!/bin/bash
################################################################################
# Gastro Kiosk Startup Script
# This script is called by gastro-kiosk.service
################################################################################

LOG_FILE="/var/log/gastro-kiosk-startup.log"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log "========================================="
log "Gastro Kiosk startup initiated"
log "========================================="

# Get configuration from environment (set by systemd service)
SERVER_IP="${SERVER_IP:-100.64.0.7}"
SERVER_PORT="${SERVER_PORT:-3001}"
DEVICE_HOSTNAME="${DEVICE_HOSTNAME:-$(hostname)}"

log "Configuration:"
log "  Server: $SERVER_IP:$SERVER_PORT"
log "  Device: $DEVICE_HOSTNAME"
log "  Display: $DISPLAY"
log "  User: $USER"

# Wait for X11 server
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

# Wait for VPN connection
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

# Wait for network connectivity
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

# Apply X11 settings
log "Applying X11 settings..."
xset s off          # Disable screensaver
xset -dpms          # Disable power management
xset s noblank      # Prevent screen blanking

# Hide cursor
log "Starting unclutter (cursor hiding)..."
unclutter -idle 0.1 -root &

# Clean up old chromium instances
log "Cleaning up old Chromium processes..."
pkill -f "chromium.*$SERVER_PORT" || true
sleep 2

# Create temporary profile directory
CHROME_PROFILE="/tmp/chromium-kiosk-$$"
mkdir -p "$CHROME_PROFILE"
log "Chromium profile: $CHROME_PROFILE"

# Build URL with deviceId
URL="https://${SERVER_IP}:${SERVER_PORT}?deviceId=${DEVICE_HOSTNAME}"
log "Application URL: $URL"

# Launch Chromium in kiosk mode
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
SCRIPT_EOF
    
    chmod +x /usr/local/bin/gastro-kiosk-start.sh
    log "Startup script created: /usr/local/bin/gastro-kiosk-start.sh"
    
    log "Creating systemd service..."
    cat > /etc/systemd/system/gastro-kiosk.service <<EOF
[Unit]
Description=Gastro Kiosk Application
After=graphical.target network-online.target tailscaled.service
Wants=network-online.target
Requires=tailscaled.service

[Service]
Type=simple
User=$DEVICE_USER
Environment="DISPLAY=:0"
Environment="XAUTHORITY=/home/$DEVICE_USER/.Xauthority"
Environment="SERVER_IP=$SERVER_IP"
Environment="SERVER_PORT=$SERVER_PORT"
Environment="DEVICE_HOSTNAME=$DEVICE_HOSTNAME"
ExecStart=/usr/local/bin/gastro-kiosk-start.sh
Restart=always
RestartSec=10
StandardOutput=append:/var/log/gastro-kiosk.log
StandardError=append:/var/log/gastro-kiosk.log

[Install]
WantedBy=graphical.target
EOF
    
    log "Enabling and starting gastro-kiosk.service..."
    systemctl daemon-reload
    systemctl enable gastro-kiosk.service
    
    # Don't start now, will start after reboot
    log_info "Service will start automatically after reboot"
    
    log "Phase 5 completed successfully"
}

phase6_heartbeat_services() {
    print_header "PHASE 6: HEARTBEAT SERVICES (OPTIONAL)"
    
    log_info "This phase installs printer and payment terminal services"
    log_info "Only needed for devices with physical hardware attached"
    echo ""
    read -p "Install printer service? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        install_printer_service
    fi
    
    echo ""
    read -p "Install payment terminal service? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        install_terminal_service
    fi
    
    log "Phase 6 completed"
}

install_printer_service() {
    log "Installing Node.js..."
    if ! command -v node &>/dev/null; then
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
        apt-get install -y -qq nodejs
    fi
    
    log "Installing printer service..."
    PRINTER_DIR="/home/$DEVICE_USER/printer-service"
    mkdir -p "$PRINTER_DIR"
    
    cat > "$PRINTER_DIR/server.js" <<'NODE_EOF'
const http = require('http');
const { exec } = require('child_process');
const axios = require('axios');

const PORT = process.env.PORT || 8083;
const DEVICE_ID = process.env.DEVICE_ID || require('os').hostname();
const DEVICE_MANAGER_URL = process.env.DEVICE_MANAGER_URL || 'http://100.64.0.7:8090';

// Heartbeat to device manager
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
            // Print logic here (escpos, etc.)
            console.log('Print request:', data);
            res.writeHead(200);
            res.end(JSON.stringify({ success: true }));
        });
    }
});

server.listen(PORT, () => {
    console.log(`Printer service listening on port ${PORT}`);
});
NODE_EOF
    
    cat > "$PRINTER_DIR/package.json" <<'JSON_EOF'
{
  "name": "printer-service",
  "version": "1.0.0",
  "main": "server.js",
  "dependencies": {
    "axios": "^1.6.0"
  }
}
JSON_EOF
    
    chown -R $DEVICE_USER:$DEVICE_USER "$PRINTER_DIR"
    su - $DEVICE_USER -c "cd $PRINTER_DIR && npm install --silent"
    
    cat > /etc/systemd/system/gastro-printer.service <<EOF
[Unit]
Description=Gastro Printer Service
After=network.target

[Service]
Type=simple
User=$DEVICE_USER
WorkingDirectory=$PRINTER_DIR
Environment="PORT=8083"
Environment="DEVICE_ID=$DEVICE_HOSTNAME"
Environment="DEVICE_MANAGER_URL=$DEVICE_MANAGER_URL"
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable gastro-printer.service
    systemctl start gastro-printer.service
    
    log "Printer service installed and started"
}

install_terminal_service() {
    log "Installing Node.js..."
    if ! command -v node &>/dev/null; then
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
        apt-get install -y -qq nodejs
    fi
    
    log "Installing payment terminal service..."
    TERMINAL_DIR="/home/$DEVICE_USER/payment-terminal-service"
    mkdir -p "$TERMINAL_DIR"
    
    cat > "$TERMINAL_DIR/server.js" <<'NODE_EOF'
const http = require('http');
const axios = require('axios');

const PORT = process.env.PORT || 8082;
const DEVICE_ID = process.env.DEVICE_ID || require('os').hostname();
const DEVICE_MANAGER_URL = process.env.DEVICE_MANAGER_URL || 'http://100.64.0.7:8090';

// Heartbeat to device manager
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
});
NODE_EOF
    
    cat > "$TERMINAL_DIR/package.json" <<'JSON_EOF'
{
  "name": "payment-terminal-service",
  "version": "1.0.0",
  "main": "server.js",
  "dependencies": {
    "axios": "^1.6.0"
  }
}
JSON_EOF
    
    chown -R $DEVICE_USER:$DEVICE_USER "$TERMINAL_DIR"
    su - $DEVICE_USER -c "cd $TERMINAL_DIR && npm install --silent"
    
    cat > /etc/systemd/system/gastro-terminal.service <<EOF
[Unit]
Description=Gastro Payment Terminal Service
After=network.target

[Service]
Type=simple
User=$DEVICE_USER
WorkingDirectory=$TERMINAL_DIR
Environment="PORT=8082"
Environment="DEVICE_ID=$DEVICE_HOSTNAME"
Environment="DEVICE_MANAGER_URL=$DEVICE_MANAGER_URL"
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable gastro-terminal.service
    systemctl start gastro-terminal.service
    
    log "Payment terminal service installed and started"
}

phase7_cleanup() {
    print_header "PHASE 7: CLEANUP & SECURITY"
    
    log "Disabling conflicting autostart methods..."
    
    # Disable any XDG autostart chromium
    if [ -f "/home/$DEVICE_USER/.config/autostart/chromium.desktop" ]; then
        mv "/home/$DEVICE_USER/.config/autostart/chromium.desktop" \
           "/home/$DEVICE_USER/.config/autostart/chromium.desktop.disabled"
        log "Disabled XDG chromium autostart"
    fi
    
    # Disable any old kiosk services
    for service in kiosk-frontend bakery-kiosk-browser kiosk-browser; do
        if systemctl list-unit-files | grep -q "$service.service"; then
            systemctl disable "$service.service" 2>/dev/null || true
            log "Disabled old service: $service.service"
        fi
    done
    
    log "Setting proper permissions..."
    chown -R $DEVICE_USER:$DEVICE_USER /home/$DEVICE_USER
    
    log "Cleaning up apt cache..."
    apt-get autoremove -y -qq
    apt-get clean
    
    log "Phase 7 completed successfully"
}

phase8_validation() {
    print_header "PHASE 8: VALIDATION"
    
    log "Running system validation checks..."
    
    local errors=0
    
    # Check user
    if id "$DEVICE_USER" &>/dev/null; then
        log "✓ User $DEVICE_USER exists"
    else
        log_error "✗ User $DEVICE_USER not found"
        ((errors++))
    fi
    
    # Check display manager
    if systemctl is-enabled lightdm &>/dev/null; then
        log "✓ LightDM is enabled"
    else
        log_error "✗ LightDM is not enabled"
        ((errors++))
    fi
    
    # Check chromium
    if command -v chromium-browser &>/dev/null; then
        log "✓ Chromium is installed"
    else
        log_error "✗ Chromium is not installed"
        ((errors++))
    fi
    
    # Check VPN
    if tailscale status | grep -q "$SERVER_IP"; then
        log "✓ VPN is connected"
    else
        log_warning "⚠ VPN is not connected (may need reboot)"
    fi
    
    # Check kiosk service
    if systemctl is-enabled gastro-kiosk.service &>/dev/null; then
        log "✓ Kiosk service is enabled"
    else
        log_error "✗ Kiosk service is not enabled"
        ((errors++))
    fi
    
    # Check startup script
    if [ -x /usr/local/bin/gastro-kiosk-start.sh ]; then
        log "✓ Startup script is executable"
    else
        log_error "✗ Startup script is missing or not executable"
        ((errors++))
    fi
    
    echo ""
    if [ $errors -eq 0 ]; then
        log "✓ All validation checks passed!"
        return 0
    else
        log_error "✗ $errors validation check(s) failed"
        return 1
    fi
}

################################################################################
# MAIN INSTALLATION FLOW
################################################################################

main() {
    print_header "GASTRO KIOSK PRO - INSTALLATION SCRIPT V2.0"
    
    log "Starting installation at $(date)"
    log "Log file: $LOG_FILE"
    
    # Pre-flight checks
    check_root
    check_ubuntu
    
    # Interactive configuration
    prompt_configuration
    
    # Installation phases
    phase1_system_preparation
    phase2_display_manager
    phase3_chromium
    phase4_vpn
    phase5_kiosk_service
    phase6_heartbeat_services
    phase7_cleanup
    phase8_validation
    
    # Final message
    print_header "INSTALLATION COMPLETED"
    
    log "Installation log saved to: $LOG_FILE"
    log "Kiosk startup log will be at: /var/log/gastro-kiosk-startup.log"
    log "Service log: journalctl -u gastro-kiosk.service -f"
    echo ""
    log_info "Next steps:"
    log_info "  1. Review the logs above for any warnings"
    log_info "  2. Reboot the system: sudo reboot"
    log_info "  3. After reboot, the kiosk application should start automatically"
    log_info "  4. If issues occur, check: journalctl -u gastro-kiosk.service"
    echo ""
    
    read -p "Reboot now? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "Rebooting system..."
        reboot
    else
        log "Installation complete. Please reboot manually when ready."
    fi
}

# Run main function
main "$@"
