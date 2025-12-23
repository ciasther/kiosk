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
readonly HEADSCALE_SERVER="http://89.72.39.90:32654"
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
    
    # Fix broken Surface Linux repository (if exists)
    if [ -f /etc/apt/sources.list.d/surfacelinux.list ]; then
        log "Detected Surface device - fixing repository configuration..."
        # Backup original
        cp /etc/apt/sources.list.d/surfacelinux.list /etc/apt/sources.list.d/surfacelinux.list.backup 2>/dev/null || true
        # Disable broken repo
        sed -i 's/^deb/#deb/g' /etc/apt/sources.list.d/surfacelinux.list || true
        log "Surface repository disabled to prevent apt errors"
    fi
    
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
            echo "$DEVICE_USER:12345" | chpasswd
            usermod -aG sudo "$DEVICE_USER"
            log "User $DEVICE_USER created with password: 12345"
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
    
    # Create log file with correct permissions
    touch /var/log/gastro-kiosk-startup.log
    chown $DEVICE_USER:$DEVICE_USER /var/log/gastro-kiosk-startup.log
    chmod 644 /var/log/gastro-kiosk-startup.log
    log "Log file created with correct permissions"
    
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
    log "Installing system dependencies for printer..."
    apt-get install -y -qq \
        python3-pip \
        python3-pil \
        libusb-1.0-0 \
        python3-usb \
        fonts-dejavu-core || {
            log_error "Failed to install printer dependencies"
            return 1
        }
    
    log "Installing Python modules for ESC/POS printer..."
    pip3 install --break-system-packages python-escpos pillow 2>/dev/null || {
        log_warning "pip3 install with --break-system-packages failed, trying without..."
        pip3 install python-escpos pillow || {
            log_error "Failed to install Python modules"
            return 1
        }
    }
    
    log "Adding user $DEVICE_USER to printer groups..."
    usermod -a -G lp,dialout $DEVICE_USER
    
    log "Disabling CUPS (conflicts with direct USB printing)..."
    systemctl stop cups cups.socket cups.path cups-browsed 2>/dev/null || true
    systemctl disable cups cups.socket cups.path cups-browsed 2>/dev/null || true
    systemctl mask cups 2>/dev/null || true  # Prevent auto-start after reboot
    
    log "Blacklisting usblp module..."
    cat > /etc/modprobe.d/blacklist-usblp.conf <<EOF
# Disable usblp kernel module for direct ESC/POS printing
blacklist usblp
EOF
    
    log "Installing Node.js..."
    if ! command -v node &>/dev/null; then
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
        apt-get install -y -qq nodejs
    fi
    
    log "Installing printer service..."
    PRINTER_DIR="/home/$DEVICE_USER/printer-service"
    mkdir -p "$PRINTER_DIR"
    
    # Create full server.js with express and print logic
    cat > "$PRINTER_DIR/server.js" <<'NODE_EOF'
const express = require('express');
const { exec } = require('child_process');
const cors = require('cors');
const axios = require('axios');
const os = require('os');

const app = express();
const PORT = process.env.PORT || 8083;
const DEVICE_ID = process.env.DEVICE_ID || os.hostname();
const DEVICE_MANAGER_URL = process.env.DEVICE_MANAGER_URL || 'http://100.64.0.7:8090';

app.use(cors());
app.use(express.json({ limit: '10mb' }));

// Heartbeat to device manager
setInterval(() => {
    const interfaces = os.networkInterfaces();
    let ip = 'unknown';
    for (const iface of Object.values(interfaces)) {
        for (const addr of iface) {
            if (addr.family === 'IPv4' && !addr.internal) {
                ip = addr.address;
                break;
            }
        }
        if (ip !== 'unknown') break;
    }
    
    axios.post(`${DEVICE_MANAGER_URL}/heartbeat`, {
        deviceId: DEVICE_ID,
        capabilities: { printer: true },
        printerPort: PORT,
        ip: ip,
        hostname: os.hostname()
    }).catch(err => console.error('Heartbeat failed:', err.message));
}, 30000);

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'printer', deviceId: DEVICE_ID, timestamp: new Date().toISOString() });
});

// Print ticket endpoint
app.post('/print', (req, res) => {
  const orderData = req.body;
  
  console.log(`[${new Date().toISOString()}] Print request for order #${orderData.orderNumber}`);
  
  // Validate order data
  if (!orderData.orderNumber || !orderData.items) {
    return res.status(400).json({ error: 'Invalid order data' });
  }
  
  // Prepare JSON for Python script
  const orderJson = JSON.stringify(orderData);
  const printScriptPath = `${process.env.HOME}/printer-service/print_ticket.py`;
  const command = `python3 ${printScriptPath} '${orderJson.replace(/'/g, "'\\''")}'`;
  
  // Execute print script
  exec(command, { timeout: 10000 }, (error, stdout, stderr) => {
    if (error) {
      console.error(`[${new Date().toISOString()}] Print error:`, stderr);
      return res.status(500).json({ 
        error: 'Print failed', 
        details: stderr,
        orderNumber: orderData.orderNumber 
      });
    }
    
    console.log(`[${new Date().toISOString()}] Print successful: ${stdout}`);
    res.json({ 
      success: true, 
      message: 'Ticket printed',
      orderNumber: orderData.orderNumber 
    });
  });
});

// Test print endpoint
app.post('/test', (req, res) => {
  const testOrder = {
    orderNumber: 999,
    items: [
      { name: 'Test Pizza', quantity: 1, price: 25.00 },
      { name: 'Test Napój', quantity: 2, price: 5.00 }
    ],
    total: 35.00,
    paymentMethod: 'TEST',
    createdAt: new Date().toISOString()
  };
  
  const orderJson = JSON.stringify(testOrder);
  const printScriptPath = `${process.env.HOME}/printer-service/print_ticket.py`;
  const command = `python3 ${printScriptPath} '${orderJson.replace(/'/g, "'\\''")}'`;
  
  exec(command, { timeout: 10000 }, (error, stdout, stderr) => {
    if (error) {
      console.error('Test print error:', stderr);
      return res.status(500).json({ error: 'Test print failed', details: stderr });
    }
    
    console.log('Test print successful:', stdout);
    res.json({ success: true, message: 'Test ticket printed' });
  });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Printer service running on http://0.0.0.0:${PORT}`);
  console.log('Endpoints:');
  console.log(`  GET  /health - Health check`);
  console.log(`  POST /print  - Print order ticket`);
  console.log(`  POST /test   - Print test ticket`);
});
NODE_EOF
    
    # Create print_ticket.py with Polish character support
    cat > "$PRINTER_DIR/print_ticket.py" <<'PYTHON_EOF'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Gastro Kiosk Pro - Thermal Printer with Polish Characters
80mm ESC/POS printer with bitmap rendering
"""

import sys
import json
from escpos.printer import Usb
from PIL import Image, ImageDraw, ImageFont
from datetime import datetime

# Hwasung printer USB identifiers
PRINTER_VID = 0x0006
PRINTER_PID = 0x000b

# Payment method translations
PAYMENT_METHOD_MAP = {
    'CASH': 'Gotówka',
    'CARD': 'Karta',
    'ONLINE': 'Online',
    'TERMINAL': 'Terminal'
}

# Centering configuration
LEFT_MARGIN = 50  # Adjust for printer alignment (20-80)

def text_to_bitmap(text, width=512, font_size=22, bold=False, left_margin=None):
    """Convert text to bitmap with Polish characters support"""
    if left_margin is None:
        left_margin = LEFT_MARGIN
    
    lines = text.split('\n')
    height = len(lines) * (font_size + 8) + 20
    total_width = width + left_margin
    
    # White background
    img = Image.new('1', (total_width, height), 1)
    draw = ImageDraw.Draw(img)
    
    # DejaVu Sans font with Polish characters
    try:
        if bold:
            font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", font_size)
        else:
            font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", font_size)
    except:
        font = ImageFont.load_default()
    
    # Draw centered lines
    y_position = 10
    for line in lines:
        if line.strip():
            bbox = draw.textbbox((0, 0), line, font=font)
            text_width = bbox[2] - bbox[0]
            x = (width - text_width) // 2 + left_margin
            x = max(left_margin, x)
            draw.text((x, y_position), line, fill=0, font=font)
        y_position += font_size + 8
    
    return img

def format_order_ticket(order_data):
    """Format order data for printing"""
    try:
        order_number = order_data.get('orderNumber', 'N/A')
        items = order_data.get('items', [])
        total = order_data.get('total', 0)
        payment_method_raw = order_data.get('paymentMethod', 'UNKNOWN')
        payment_method = PAYMENT_METHOD_MAP.get(payment_method_raw, payment_method_raw)
        created_at = order_data.get('createdAt', datetime.now().isoformat())
        
        try:
            dt = datetime.fromisoformat(created_at.replace('Z', '+00:00'))
            time_str = dt.strftime('%Y-%m-%d %H:%M:%S')
        except:
            time_str = str(created_at)
        
        return {
            'orderNumber': order_number,
            'items': items,
            'total': total,
            'paymentMethod': payment_method,
            'timestamp': time_str
        }
    except Exception as e:
        print(f"Format error: {e}", file=sys.stderr)
        return None

def print_ticket(order_data):
    """Print ticket with Polish characters and manual centering"""
    try:
        printer = Usb(PRINTER_VID, PRINTER_PID, timeout=5000, in_ep=0x82, out_ep=0x01)
        printer.text('\x1b\x40')  # Initialize printer
        
        # Header
        header = text_to_bitmap("GASTRO KIOSK PRO", width=512, font_size=24, bold=True)
        printer.image(header, impl="bitImageRaster")
        
        separator = text_to_bitmap("=" * 32, width=512, font_size=16)
        printer.image(separator, impl="bitImageRaster")
        
        # Order number (large)
        order_num_text = f"#{order_data['orderNumber']}"
        order_number_img = text_to_bitmap(order_num_text, width=512, font_size=88, bold=True)
        printer.image(order_number_img, impl="bitImageRaster")
        
        printer.image(separator, impl="bitImageRaster")
        
        # Details
        details = f"Data: {order_data['timestamp']}\nPłatność: {order_data['paymentMethod']}"
        details_img = text_to_bitmap(details, width=512, font_size=18)
        printer.image(details_img, impl="bitImageRaster")
        
        dash_separator = text_to_bitmap("-" * 32, width=512, font_size=16)
        printer.image(dash_separator, impl="bitImageRaster")
        
        # Items header
        items_header = text_to_bitmap("POZYCJE:", width=512, font_size=20, bold=True)
        printer.image(items_header, impl="bitImageRaster")
        printer.image(dash_separator, impl="bitImageRaster")
        
        # Print each item
        for item in order_data['items']:
            name = item.get('name', 'Unknown')
            quantity = item.get('quantity', 1)
            price = item.get('price', 0)
            total_item = quantity * price
            
            item_name_img = text_to_bitmap(name, width=512, font_size=20, bold=True)
            printer.image(item_name_img, impl="bitImageRaster")
            
            item_details = f"{quantity} x {price:.2f} PLN = {total_item:.2f} PLN"
            item_details_img = text_to_bitmap(item_details, width=512, font_size=18)
            printer.image(item_details_img, impl="bitImageRaster")
        
        printer.image(dash_separator, impl="bitImageRaster")
        
        # Total
        total_text = f"SUMA: {order_data['total']:.2f} PLN"
        total_img = text_to_bitmap(total_text, width=512, font_size=32, bold=True)
        printer.image(total_img, impl="bitImageRaster")
        
        printer.image(separator, impl="bitImageRaster")
        
        # Footer
        footer = text_to_bitmap("Dziękujemy za zamówienie!\nSmacznego!", width=512, font_size=20)
        printer.image(footer, impl="bitImageRaster")
        
        printer.ln(3)
        printer.cut(mode='FULL')
        printer.close()
        
        print("✓ Ticket printed successfully", file=sys.stderr)
        return True
        
    except Exception as e:
        print(f"✗ Print error: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc(file=sys.stderr)
        return False

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 print_ticket.py '<json_order_data>'", file=sys.stderr)
        sys.exit(1)
    
    try:
        order_json = sys.argv[1]
        order_raw = json.loads(order_json)
        order_data = format_order_ticket(order_raw)
        if not order_data:
            print("Format error", file=sys.stderr)
            sys.exit(1)
        
        if print_ticket(order_data):
            print("SUCCESS")
            sys.exit(0)
        else:
            print("FAILED")
            sys.exit(1)
            
    except json.JSONDecodeError as e:
        print(f"Invalid JSON: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
PYTHON_EOF
    
    chmod +x "$PRINTER_DIR/print_ticket.py"
    
    cat > "$PRINTER_DIR/package.json" <<'JSON_EOF'
{
  "name": "printer-service",
  "version": "1.0.0",
  "main": "server.js",
  "dependencies": {
    "express": "^4.18.0",
    "cors": "^2.8.5",
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
Environment="HOME=/home/$DEVICE_USER"
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable gastro-printer.service
    systemctl start gastro-printer.service
    
    log "Printer service installed and started successfully"
    log "Testing printer service..."
    sleep 2
    curl -s http://localhost:8083/health || log_warning "Printer service health check failed"
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
    axios.post(`${DEVICE_MANAGER_URL}/heartbeat`, {
        deviceId: DEVICE_ID,
        capabilities: { paymentTerminal: true },
        ip: require('os').networkInterfaces().eth0?.[0]?.address || 'unknown',
        hostname: require('os').hostname()
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
