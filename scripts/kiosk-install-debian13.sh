#!/bin/bash
################################################################################
# Gastro Kiosk Pro - Debian 13 Installation Script v3.0
# 
# Features:
#   - LightDM + Openbox (minimal kiosk, no GNOME)
#   - Auto-detection of USB printers with VID/PID injection
#   - Payment terminal heartbeat (device-manager integration)
#   - Hard restart on timeout (no hanging)
#   - Python venv for Debian 13 PEP 668 compliance
#   - Full validation and retry logic
#   - Polish characters support via bitmap rendering
#
# Requirements:
#   - Fresh Debian 13 (Trixie)
#   - Internet connection
#   - sudo privileges
#
# Usage:
#   sudo bash kiosk-install-debian13.sh
#
# Version: 3.0.0
# Date: 2025-12-28
################################################################################

set -u  # Exit on undefined variable

################################################################################
# CONFIGURATION
################################################################################

# Server configuration
readonly SERVER_IP="100.64.0.7"
SERVER_PORT="3001"  # Will be set based on device role
readonly DEVICE_MANAGER_URL="http://${SERVER_IP}:8090"
readonly BACKEND_URL="https://${SERVER_IP}:3000"

# Headscale/Tailscale configuration
readonly HEADSCALE_SERVER="http://89.72.39.90:32654"
readonly AUTHKEY_PLACEHOLDER="YOUR_AUTHKEY_HERE"

# Device configuration
DEVICE_ROLE="customer"  # customer, cashier, display
DEVICE_USER=""
DEVICE_HOSTNAME=""
USER_RUNNING="${SUDO_USER:-$(logname 2>/dev/null || echo '')}"  # User who ran sudo

# Printer configuration (will be auto-detected)
PRINTER_VID="0x0006"  # Default fallback (Hwasung)
PRINTER_PID="0x000b"  # Default fallback

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

check_debian() {
    if ! grep -q "Debian" /etc/os-release; then
        log_error "This script is designed for Debian. Detected: $(cat /etc/os-release | grep PRETTY_NAME)"
        exit 1
    fi
    
    local version=$(grep VERSION_ID /etc/os-release | cut -d'"' -f2)
    log_info "Detected Debian version: $version"
    
    if [[ ! "$version" =~ ^13 ]]; then
        log_warning "This script is optimized for Debian 13. Current: $version"
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
    DEFAULT_HOSTNAME="kiosk-deb-$(date +%s | tail -c 5)"
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
# AUTO-DETECTION FUNCTIONS
################################################################################

detect_printer() {
    print_header "AUTO-DETECTING USB PRINTER"
    
    log "Scanning USB devices for printers..."
    
    # Global flag for printer detection
    PRINTER_DETECTED=false
    
    # Create temporary Python script for USB detection
    cat > /tmp/detect_printer.py <<'PYTHON_EOF'
#!/usr/bin/env python3
import sys
try:
    import usb.core
    import usb.util
    
    # Find all USB devices
    devices = usb.core.find(find_all=True)
    found = False
    
    for device in devices:
        try:
            # Check if device has printer class interface (class 7)
            for cfg in device:
                for intf in cfg:
                    if intf.bInterfaceClass == 7:  # Printer class
                        print(f"0x{device.idVendor:04x}:0x{device.idProduct:04x}")
                        found = True
                        break
                if found:
                    break
        except:
            pass
        
        if found:
            break
    
    # Fallback: Check known thermal printer vendors
    if not found:
        known_vendors = {
            0x0006: "Hwasung",
            0x04b8: "Epson", 
            0x0519: "Star Micronics",
            0x154f: "Wincor Nixdorf"
        }
        
        for device in usb.core.find(find_all=True):
            if device.idVendor in known_vendors:
                print(f"0x{device.idVendor:04x}:0x{device.idProduct:04x}")
                found = True
                break
    
    if not found:
        sys.exit(1)
        
except ImportError:
    print("ERROR: python3-usb not installed", file=sys.stderr)
    sys.exit(2)
except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(3)
PYTHON_EOF
    
    chmod +x /tmp/detect_printer.py
    
    # Try to detect printer
    if DETECTED=$(python3 /tmp/detect_printer.py 2>/dev/null); then
        PRINTER_VID=$(echo "$DETECTED" | cut -d: -f1)
        PRINTER_PID=$(echo "$DETECTED" | cut -d: -f2)
        PRINTER_DETECTED=true
        log "✓ Printer detected: VID=$PRINTER_VID PID=$PRINTER_PID"
        
        # Show device info from lsusb
        local device_info=$(lsusb -d ${PRINTER_VID#0x}:${PRINTER_PID#0x} 2>/dev/null)
        if [[ -n "$device_info" ]]; then
            log_info "  Device: $device_info"
        fi
    else
        log_warning "⚠ No USB printer detected automatically"
        log_warning "  Printer service will not be installed"
    fi
    
    rm -f /tmp/detect_printer.py
    
    log_info "Printer configuration: VID=$PRINTER_VID PID=$PRINTER_PID"
}

detect_terminal() {
    print_header "AUTO-DETECTING PAYMENT TERMINAL"
    
    log "Scanning for Ingenico terminal..."
    
    # Global flag for terminal detection
    TERMINAL_DETECTED=false
    
    # Check for Ingenico MAC address (known terminal: 10:1e:da:45:37:ce)
    if arp -a | grep -qi "10:1e:da"; then
        TERMINAL_DETECTED=true
        TERMINAL_IP=$(arp -a | grep -i "10:1e:da" | awk '{print $2}' | tr -d '()')
        log "✓ Ingenico terminal detected via ARP"
        log_info "  MAC: 10:1e:da:xx:xx:xx"
        log_info "  IP: $TERMINAL_IP (if available)"
    fi
    
    # Check for terminal on known subnet (10.42.0.x)
    if ! $TERMINAL_DETECTED; then
        if ip addr show | grep -q "10.42.0"; then
            log_info "Found NAT subnet 10.42.0.x - terminal might be connected"
            # Ping sweep to find terminal
            for i in {70..80}; do
                if ping -c 1 -W 1 10.42.0.$i &>/dev/null; then
                    TERMINAL_IP="10.42.0.$i"
                    TERMINAL_DETECTED=true
                    log "✓ Device found at 10.42.0.$i (possible terminal)"
                    break
                fi
            done
        fi
    fi
    
    if $TERMINAL_DETECTED; then
        log "✓ Payment terminal detected - service will be installed"
        log_warning "  Terminal TID will use placeholder (configure later in .env)"
    else
        log_warning "⚠ No payment terminal detected"
        log_warning "  Payment terminal service will not be installed"
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
                log_error "apt-get update failed after 3 attempts. Cannot continue."
                exit 1
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
        openssh-server \
        vim \
        unzip \
        ca-certificates \
        gnupg \
        lsb-release \
        software-properties-common \
        usbutils \
        build-essential || {
            log_warning "Some packages failed to install. Trying essential ones only..."
            apt-get install -y -qq curl wget ca-certificates usbutils openssh-server || {
                log_error "Critical: Cannot install essential packages"
                exit 1
            }
        }
    
    log "Enabling and starting SSH server..."
    systemctl enable ssh
    systemctl start ssh
    
    log "Installing Python dependencies..."
    apt-get install -y -qq \
        python3 \
        python3-pip \
        python3-venv \
        python3-pil \
        python3-usb \
        fonts-dejavu-core \
        libusb-1.0-0 || {
            log_error "Failed to install Python dependencies"
            exit 1
        }
    
    log "Creating user: $DEVICE_USER"
    if ! id "$DEVICE_USER" &>/dev/null; then
        if useradd -m -s /bin/bash "$DEVICE_USER"; then
            echo "$DEVICE_USER:12345" | chpasswd
            usermod -aG sudo,plugdev,dialout,lp,video,audio "$DEVICE_USER"
            log "User $DEVICE_USER created with password: 12345"
        else
            log_error "Failed to create user $DEVICE_USER"
            exit 1
        fi
    else
        log_info "User $DEVICE_USER already exists"
        # Ensure user is in correct groups
        usermod -aG sudo,plugdev,dialout,lp,video,audio "$DEVICE_USER"
    fi
    
    log "Checking for monitor configuration to inherit..."
    # Copy monitors.xml from running user (if exists) to new kiosk user
    if [ -n "$USER_RUNNING" ] && [ -f "/home/$USER_RUNNING/.config/monitors.xml" ]; then
        log "Found monitors.xml from $USER_RUNNING - copying to $DEVICE_USER"
        mkdir -p /home/$DEVICE_USER/.config
        cp /home/$USER_RUNNING/.config/monitors.xml /home/$DEVICE_USER/.config/
        chown -R $DEVICE_USER:$DEVICE_USER /home/$DEVICE_USER/.config
        log "Monitor configuration inherited successfully (rotation, resolution, etc.)"
    else
        log_warning "No monitors.xml found in /home/$USER_RUNNING/.config/"
        log_warning "If using vertical display, configure rotation manually before running this script"
    fi
    
    log "Phase 1 completed successfully"
}

phase2_lightdm_openbox() {
    print_header "PHASE 2: LIGHTDM + OPENBOX (MINIMAL KIOSK)"
    
    log "Installing LightDM, Xorg, and Openbox..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        lightdm \
        xserver-xorg \
        xserver-xorg-video-all \
        xserver-xorg-input-all \
        xinit \
        x11-xserver-utils \
        openbox \
        obconf \
        unclutter \
        xdotool || {
            log_error "Failed to install LightDM/Openbox"
            exit 1
        }
    
    log "Configuring LightDM auto-login..."
    local lightdm_conf="/etc/lightdm/lightdm.conf"
    
    # Backup if exists
    [ -f "$lightdm_conf" ] && cp "$lightdm_conf" "${lightdm_conf}.backup-$(date +%Y%m%d)"
    
    # Create/update LightDM configuration
    cat > "$lightdm_conf" <<LIGHTDM_EOF
[Seat:*]
autologin-user=$DEVICE_USER
autologin-user-timeout=0
autologin-session=openbox
user-session=openbox
greeter-session=lightdm-gtk-greeter
LIGHTDM_EOF
    
    log "✓ LightDM configured for auto-login as: $DEVICE_USER"
    
    log "Configuring Openbox (minimal window manager)..."
    
    # Create Openbox config directory
    mkdir -p /home/$DEVICE_USER/.config/openbox
    
    # Openbox autostart script (replaces GNOME autostart)
    cat > /home/$DEVICE_USER/.config/openbox/autostart <<'OPENBOX_EOF'
#!/bin/bash
# Openbox Autostart for Kiosk Mode

# Disable screen blanking and DPMS
xset s off
xset s noblank
xset -dpms

# Hide mouse cursor after 1s of inactivity
unclutter -idle 1 -root &

# Small delay to ensure X11 is fully ready before applying xrandr
sleep 2

# Wait for VPN (if needed) and launch kiosk application
/usr/local/bin/gastro-kiosk-start.sh &
OPENBOX_EOF
    
    chmod +x /home/$DEVICE_USER/.config/openbox/autostart
    
    # Minimal Openbox rc.xml (no decorations, no panels)
    cat > /home/$DEVICE_USER/.config/openbox/rc.xml <<'OPENBOX_RC_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc">
  <applications>
    <application class="Chromium*">
      <decor>no</decor>
      <fullscreen>yes</fullscreen>
      <focus>yes</focus>
      <layer>above</layer>
    </application>
  </applications>
  <keyboard>
    <!-- Disable Alt+F4 -->
    <keybind key="A-F4"><action name="Execute"><execute>true</execute></action></keybind>
  </keyboard>
</openbox_config>
OPENBOX_RC_EOF
    
    chown -R $DEVICE_USER:$DEVICE_USER /home/$DEVICE_USER/.config
    
    log "✓ Openbox configured for fullscreen kiosk mode"
    
    # Auto-detect vertical display and add xrandr rotation
    log "Checking for vertical display configuration..."
    if [ -f "/home/$DEVICE_USER/.config/monitors.xml" ]; then
        if grep -q '<rotation>right</rotation>' "/home/$DEVICE_USER/.config/monitors.xml"; then
            log "Detected vertical display rotation (right) in monitors.xml"
            log_warning "Note: monitors.xml only works with GNOME. Adding xrandr for openbox..."
            
            # Add xrandr with dynamic output detection (will run when X11 is ready)
            sed -i "/gastro-kiosk-start.sh/i # Rotate display to vertical (auto-detected from monitors.xml)\nPRIMARY_OUTPUT=\$(xrandr 2>/dev/null | grep ' connected primary' | awk '{print \$1}' || echo 'HDMI-1')\nxrandr --output \"\$PRIMARY_OUTPUT\" --rotate right\n" \
                "/home/$DEVICE_USER/.config/openbox/autostart"
            
            log "✓ Added xrandr rotation (will auto-detect output at runtime)"
            
        elif grep -q '<rotation>left</rotation>' "/home/$DEVICE_USER/.config/monitors.xml"; then
            log "Detected vertical display rotation (left) in monitors.xml"
            log_warning "Note: monitors.xml only works with GNOME. Adding xrandr for openbox..."
            
            sed -i "/gastro-kiosk-start.sh/i # Rotate display to vertical (auto-detected from monitors.xml)\nPRIMARY_OUTPUT=\$(xrandr 2>/dev/null | grep ' connected primary' | awk '{print \$1}' || echo 'HDMI-1')\nxrandr --output \"\$PRIMARY_OUTPUT\" --rotate left\n" \
                "/home/$DEVICE_USER/.config/openbox/autostart"
            
            log "✓ Added xrandr rotation (will auto-detect output at runtime)"
        else
            log_info "No vertical rotation detected in monitors.xml"
        fi
    else
        log_info "No monitors.xml found - using default horizontal orientation"
    fi
    
    log "Setting LightDM as default display manager..."
    echo "/usr/sbin/lightdm" > /etc/X11/default-display-manager
    DEBIAN_FRONTEND=noninteractive dpkg-reconfigure lightdm 2>/dev/null || true
    
    log "Purging GNOME Keyring (prevents password prompts)..."
    # LightDM/Openbox doesn't need gnome-keyring
    # Chromium will use --password-store=basic instead
    apt-get purge -y gnome-keyring gnome-keyring-pkcs11 libpam-gnome-keyring 2>&1 | tee -a "$LOG_FILE" || {
        log_warning "gnome-keyring not installed (skipping)"
    }
    
    # Clean up any leftover keyring files
    rm -rf /home/$DEVICE_USER/.local/share/keyrings 2>/dev/null || true
    
    log "✓ GNOME Keyring removed"
    
    log "Phase 2 completed successfully"
}

phase3_chromium() {
    print_header "PHASE 3: CHROMIUM BROWSER"
    
    log "Installing Chromium browser..."
    # Debian 13 has chromium in standard repo (no snap needed)
    apt-get install -y -qq chromium || {
        log_error "Failed to install Chromium"
        exit 1
    }
    
    # Verify installation
    if ! command -v chromium &>/dev/null; then
        log_error "Chromium binary not found after installation"
        exit 1
    fi
    
    log "Chromium installed successfully"
    chromium --version 2>&1 | head -1 | tee -a "$LOG_FILE"
    
    log "Installing xdotool for fullscreen automation..."
    apt-get install -y -qq xdotool || {
        log_error "Failed to install xdotool"
        exit 1
    }
    
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
    
    # Enable and start tailscaled
    systemctl enable tailscaled
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
                log_warning "Failed to connect to Headscale. Service will retry on boot."
            fi
        fi
    done
    
    log "Waiting for VPN connection..."
    for i in {1..30}; do
        if tailscale status | grep -q "$SERVER_IP"; then
            log "VPN connected successfully!"
            tailscale status | grep "$SERVER_IP" | tee -a "$LOG_FILE"
            break
        fi
        sleep 2
        if [[ $i -eq 30 ]]; then
            log_warning "VPN connection timeout. Service will retry on boot. Continuing..."
        fi
    done
    
    log "Phase 4 completed successfully"
}

phase5_kiosk_service() {
    print_header "PHASE 5: KIOSK STARTUP SERVICE"
    
    log "Creating kiosk startup script with HARD RESTART on timeout..."
    cat > /usr/local/bin/gastro-kiosk-start.sh <<'STARTUP_EOF'
#!/bin/bash
################################################################################
# Gastro Kiosk Startup Script - Debian 13 with HARD RESTART on failure
################################################################################

LOG_FILE="$HOME/.local/log/chromium-kiosk.log"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE" >&2
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
log "  XDG_SESSION_TYPE: $XDG_SESSION_TYPE"

# Apply GNOME settings (idempotent)
# Wait for X11 display server
log "Waiting for X11 display server..."
TIMEOUT=60
COUNTER=0
while ! xset q &>/dev/null; do
    sleep 1
    ((COUNTER++))
    if [[ $COUNTER -ge $TIMEOUT ]]; then
        log_error "X11 server timeout after ${TIMEOUT}s - TRIGGERING HARD RESTART"
        log_error "Attempting to restart LightDM..."
        systemctl restart lightdm
        sleep 10
        
        # If still not working, reboot the machine
        if ! xset q &>/dev/null; then
            log_error "LightDM restart failed - HARD REBOOTING SYSTEM"
            sync
            reboot -f
        fi
        break
    fi
done

log "X11 display server ready: $DISPLAY"

# Wait for VPN connection with HARD RESTART on timeout
log "Waiting for VPN connection..."
TIMEOUT=120
COUNTER=0
while ! tailscale status 2>/dev/null | grep -q "$SERVER_IP"; do
    sleep 2
    ((COUNTER+=2))
    
    if [[ $COUNTER -ge 60 ]] && [[ $((COUNTER % 60)) -eq 0 ]]; then
        log_error "VPN connection timeout at ${COUNTER}s - attempting restart..."
        systemctl restart tailscaled
    fi
    
    if [[ $COUNTER -ge $TIMEOUT ]]; then
        log_error "VPN connection FAILED after ${TIMEOUT}s - HARD REBOOTING SYSTEM"
        log_error "This usually indicates network issues or VPN misconfiguration"
        sync
        reboot -f
    fi
done

log "VPN connected successfully!"
tailscale status | grep "$SERVER_IP" | tee -a "$LOG_FILE"

# Wait for server connectivity with HARD RESTART on timeout
log "Testing connectivity to server..."
TIMEOUT=90
COUNTER=0
while ! curl -k -s -o /dev/null -w "%{http_code}" "https://$SERVER_IP:$SERVER_PORT" | grep -q "200\|301\|302"; do
    sleep 2
    ((COUNTER+=2))
    
    if [[ $COUNTER -ge $TIMEOUT ]]; then
        log_error "Server unreachable after ${TIMEOUT}s - HARD REBOOTING SYSTEM"
        log_error "Server: https://$SERVER_IP:$SERVER_PORT"
        sync
        reboot -f
    fi
done

log "Server is reachable!"

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

# Set display variables for X11
export DISPLAY=:0
export XDG_RUNTIME_DIR="/run/user/\$(id -u)"

# Launch Chromium in kiosk mode (X11 native)
log "Launching Chromium browser..."
chromium \
    --kiosk \
    --no-first-run \
    --disable-infobars \
    --disable-features=TranslateUI \
    --disable-translate \
    --disable-session-crashed-bubble \
    --disable-component-update \
    --noerrdialogs \
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
    --password-store=basic \
    --user-data-dir="$CHROME_PROFILE" \
    "$URL" \
    >> "$LOG_FILE" 2>&1 &

CHROME_PID=$!
log "Chromium started with PID: $CHROME_PID"

# Chromium on X11 with Openbox should handle fullscreen automatically
# Openbox rc.xml forces <fullscreen>yes</fullscreen> for Chromium class

# Keep script running
wait $CHROME_PID
STARTUP_EOF
    
    chmod +x /usr/local/bin/gastro-kiosk-start.sh
    
    # Verify the file was created with content
    if [ ! -s /usr/local/bin/gastro-kiosk-start.sh ]; then
        log_error "CRITICAL: gastro-kiosk-start.sh is empty (0 bytes)"
        log_error "This will cause black screen - aborting installation"
        log_error "Heredoc may have failed. Check script syntax or disk space."
        exit 1
    fi
    
    FILE_SIZE=$(wc -l /usr/local/bin/gastro-kiosk-start.sh | awk '{print $1}')
    log "Startup script created successfully: $FILE_SIZE lines"
    
    log "Creating GNOME autostart desktop entry..."
    mkdir -p /home/$DEVICE_USER/.config/autostart
    
    cat > /home/$DEVICE_USER/.config/autostart/gastro-kiosk.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Gastro Kiosk Application
Exec=/usr/local/bin/gastro-kiosk-start.sh
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=15
EOF
    
    chown -R $DEVICE_USER:$DEVICE_USER /home/$DEVICE_USER/.config
    
    # Create log directory in user home (not /var/log - permission issues)
    mkdir -p /home/$DEVICE_USER/.local/log
    touch /home/$DEVICE_USER/.local/log/chromium-kiosk.log
    chown -R $DEVICE_USER:$DEVICE_USER /home/$DEVICE_USER/.local
    chmod 644 /home/$DEVICE_USER/.local/log/chromium-kiosk.log
    
    log "Autostart configured - application will launch after user login"
    log "Phase 5 completed successfully"
}

phase6_printer_service() {
    print_header "PHASE 6: PRINTER SERVICE (AUTO-INSTALL)"
    
    # Auto-install if printer was detected
    if [[ "$PRINTER_DETECTED" != "true" ]]; then
        log "No printer detected - skipping printer service installation"
        log "Phase 6 skipped"
        return 0
    fi
    
    log "Printer detected (VID=$PRINTER_VID PID=$PRINTER_PID) - installing service..."
    
    log "Installing Node.js..."
    if ! command -v node &>/dev/null; then
        log "Downloading Node.js setup script..."
        if ! curl -fsSL https://deb.nodesource.com/setup_20.x | bash -; then
            log_error "Failed to download Node.js setup script"
            return 1
        fi
        
        log "Installing Node.js package..."
        if ! apt-get install -y -qq nodejs 2>&1 | tee -a "$LOG_FILE"; then
            log_error "Failed to install Node.js"
            return 1
        fi
        
        if ! command -v node &>/dev/null; then
            log_error "Node.js installation failed - binary not found"
            return 1
        fi
        
        log "Node.js installed successfully: $(node --version)"
    else
        log_info "Node.js already installed: $(node --version)"
    fi
    
    log "Disabling CUPS (conflicts with direct USB printing)..."
    systemctl stop cups cups.socket cups.path cups-browsed 2>/dev/null || true
    systemctl disable cups cups.socket cups.path cups-browsed 2>/dev/null || true
    systemctl mask cups 2>/dev/null || true
    
    log "Blacklisting usblp module..."
    cat > /etc/modprobe.d/blacklist-usblp.conf <<EOF
# Disable usblp kernel module for direct ESC/POS printing
blacklist usblp
EOF
    
    # Unload if currently loaded
    rmmod usblp 2>/dev/null || true
    
    log "Installing printer service..."
    PRINTER_DIR="/home/$DEVICE_USER/printer-service"
    mkdir -p "$PRINTER_DIR"
    
    log "Creating Python virtual environment..."
    python3 -m venv "$PRINTER_DIR/venv"
    
    log "Installing Python packages in venv..."
    "$PRINTER_DIR/venv/bin/pip" install --upgrade pip --quiet
    "$PRINTER_DIR/venv/bin/pip" install python-escpos pillow pyusb --quiet
    
    log "Creating Node.js server..."
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

function getVpnIp() {
    const interfaces = os.networkInterfaces();
    
    // Priority 1: tailscale0 (VPN)
    if (interfaces.tailscale0) {
        for (const addr of interfaces.tailscale0) {
            if (addr.family === 'IPv4') {
                return addr.address;
            }
        }
    }
    
    // Fallback: any non-internal IPv4
    for (const iface of Object.values(interfaces)) {
        for (const addr of iface) {
            if (addr.family === 'IPv4' && !addr.internal) {
                return addr.address;
            }
        }
    }
    
    return 'unknown';
}

// Heartbeat to device manager
setInterval(() => {
    const ip = getVpnIp();
    
    axios.post(`${DEVICE_MANAGER_URL}/heartbeat`, {
        deviceId: DEVICE_ID,
        capabilities: { printer: true, printerPort: PORT },
        ip: ip,
        hostname: os.hostname()
    })
    .then(() => console.log(`[Heartbeat] OK - ${DEVICE_ID} @ ${ip}`))
    .catch(err => console.error('[Heartbeat] Failed:', err.message));
}, 30000);

// Send first heartbeat immediately
setTimeout(() => {
    const ip = getVpnIp();
    
    axios.post(`${DEVICE_MANAGER_URL}/heartbeat`, {
        deviceId: DEVICE_ID,
        capabilities: { printer: true, printerPort: PORT },
        ip: ip,
        hostname: os.hostname()
    })
    .then(() => console.log(`[Heartbeat] Initial OK - ${DEVICE_ID} @ ${ip}`))
    .catch(err => console.error('[Heartbeat] Initial Failed:', err.message));
}, 2000);

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'printer', deviceId: DEVICE_ID, timestamp: new Date().toISOString() });
});

// Print ticket endpoint
app.post('/print', (req, res) => {
  const orderData = req.body;
  
  console.log(`[${new Date().toISOString()}] Print request for order #${orderData.orderNumber}`);
  
  if (!orderData.orderNumber || !orderData.items) {
    return res.status(400).json({ error: 'Invalid order data' });
  }
  
  const orderJson = JSON.stringify(orderData);
  const printScriptPath = `${process.env.HOME}/printer-service/venv/bin/python3`;
  const scriptPath = `${process.env.HOME}/printer-service/print_ticket.py`;
  const command = `${printScriptPath} ${scriptPath} '${orderJson.replace(/'/g, "'\\''")}'`;
  
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
  const printScriptPath = `${process.env.HOME}/printer-service/venv/bin/python3`;
  const scriptPath = `${process.env.HOME}/printer-service/print_ticket.py`;
  const command = `${printScriptPath} ${scriptPath} '${orderJson.replace(/'/g, "'\\''")}'`;
  
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
    
    log "Creating Python printer script with auto-detected VID/PID..."
    # CRITICAL: Inject detected VID/PID into Python script
    cat > "$PRINTER_DIR/print_ticket.py" <<PYTHON_EOF
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Gastro Kiosk Pro - Thermal Printer with Polish Characters
80mm ESC/POS printer with bitmap rendering
Auto-configured for: VID=$PRINTER_VID PID=$PRINTER_PID
"""

import sys
import json
from escpos.printer import Usb
from PIL import Image, ImageDraw, ImageFont
from datetime import datetime

# AUTO-DETECTED USB IDENTIFIERS
PRINTER_VID = $PRINTER_VID
PRINTER_PID = $PRINTER_PID

# Payment method translations
PAYMENT_METHOD_MAP = {
    'CASH': 'Gotówka',
    'CARD': 'Karta',
    'ONLINE': 'Online',
    'TERMINAL': 'Terminal'
}

# Centering configuration
LEFT_MARGIN = 50

def text_to_bitmap(text, width=512, font_size=22, bold=False, left_margin=None):
    """Convert text to bitmap with Polish characters support"""
    if left_margin is None:
        left_margin = LEFT_MARGIN
    
    lines = text.split('\n')
    height = len(lines) * (font_size + 8) + 20
    total_width = width + left_margin
    
    img = Image.new('1', (total_width, height), 1)
    draw = ImageDraw.Draw(img)
    
    try:
        if bold:
            font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", font_size)
        else:
            font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", font_size)
    except:
        font = ImageFont.load_default()
    
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
        printer.text('\x1b\x40')
        
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
    
    log "Installing npm dependencies..."
    if ! su - $DEVICE_USER -c "cd $PRINTER_DIR && npm install --silent" 2>&1 | tee -a "$LOG_FILE"; then
        log_warning "npm install failed with --silent, trying verbose..."
        if ! su - $DEVICE_USER -c "cd $PRINTER_DIR && npm install" 2>&1 | tee -a "$LOG_FILE"; then
            log_error "Failed to install npm dependencies"
            return 1
        fi
    fi
    
    if [ ! -d "$PRINTER_DIR/node_modules" ]; then
        log_error "npm install completed but node_modules not found"
        return 1
    fi
    
    log "Creating systemd service..."
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
    
    if ! systemctl enable gastro-printer.service 2>&1 | tee -a "$LOG_FILE"; then
        log_error "Failed to enable gastro-printer.service"
        return 1
    fi
    
    if ! systemctl start gastro-printer.service 2>&1 | tee -a "$LOG_FILE"; then
        log_error "Failed to start gastro-printer.service"
        log_error "Check logs: journalctl -u gastro-printer.service -n 50"
        return 1
    fi
    
    log "Printer service installed and started"
    log "Testing printer service..."
    sleep 3
    
    if curl -s http://localhost:8083/health | grep -q '"status":"ok"'; then
        log "✓ Printer service health check passed"
        log_info "Printer configured with VID=$PRINTER_VID PID=$PRINTER_PID"
    else
        log_warning "⚠ Printer service health check failed - service may not be ready yet"
        log_warning "Check logs: journalctl -u gastro-printer.service -f"
    fi
    
    log "Phase 6 completed successfully"
}

phase7_terminal_service() {
    print_header "PHASE 7: PAYMENT TERMINAL SERVICE (AUTO-INSTALL)"
    
    # Auto-install if terminal was detected
    if [[ "$TERMINAL_DETECTED" != "true" ]]; then
        log "No payment terminal detected - skipping terminal service installation"
        log "Phase 7 skipped"
        return 0
    fi
    
    log "Payment terminal detected - installing service..."
    
    # Use placeholder TID (user will configure later)
    TERMINAL_TID="00000000"
    log_warning "Using placeholder TID: $TERMINAL_TID"
    log_warning "Configure actual TID later in: ~/payment-terminal-service/.env"
    log_warning "  Terminal: Menu → Zarządzanie → Wizytówka → TID"
    
    log "Installing payment terminal service..."
    log_info "Terminal TID: $TERMINAL_TID"
    TERMINAL_DIR="/home/$DEVICE_USER/payment-terminal-service"
    
    # Verify git is installed
    if ! command -v git &>/dev/null; then
        log_warning "Git not found - installing..."
        if ! apt-get install -y -qq git 2>&1 | tee -a "$LOG_FILE"; then
            log_error "Failed to install git. Terminal service requires git to download from GitHub."
            log_error "Please install manually: apt-get install -y git"
            return 1
        fi
        log "✓ Git installed successfully"
    fi
    
    log "Downloading terminal service from GitHub..."
    if ! git clone -b payment-terminal-service https://github.com/ciasther/kiosk.git /tmp/kiosk-terminal 2>&1 | tee -a "$LOG_FILE"; then
        log_error "Failed to download terminal service from GitHub"
        log_error "Check internet connection and GitHub repository access"
        return 1
    fi
    
    if [ ! -d "/tmp/kiosk-terminal" ]; then
        log_error "Terminal service directory not found after clone"
        return 1
    fi
    
    # Copy files to destination
    cp -r /tmp/kiosk-terminal "$TERMINAL_DIR"
    rm -rf /tmp/kiosk-terminal
    
    log "✓ Terminal service files downloaded"
    
    # Check if Node.js is already installed (from printer service)
    if ! command -v node &>/dev/null; then
        log "Node.js not found - installing..."
        if ! curl -fsSL https://deb.nodesource.com/setup_20.x | bash -; then
            log_error "Failed to download Node.js setup script"
            return 1
        fi
        
        if ! apt-get install -y -qq nodejs 2>&1 | tee -a "$LOG_FILE"; then
            log_error "Failed to install Node.js"
            return 1
        fi
        
        log "Node.js installed successfully: $(node --version)"
    else
        log_info "Node.js already installed: $(node --version)"
    fi
    
    # Files already downloaded from GitHub, just ensure directories exist
    mkdir -p "$TERMINAL_DIR/logs"
    
    log "Verifying terminal service files..."
    
    # Verify critical files exist
    if [ ! -f "$TERMINAL_DIR/server.js" ]; then
        log_error "server.js not found - GitHub clone may have failed"
        return 1
    fi
    
    if [ ! -f "$TERMINAL_DIR/src/terminal/client.js" ]; then
        log_error "PeP protocol files not found - GitHub clone incomplete"
        return 1
    fi
    
    log "✓ All terminal service files verified"
    
    log "Creating .env configuration with your terminal TID..."
    cat > "$TERMINAL_DIR/.env" <<EOF
# Terminal Configuration
# Auto-generated by kiosk-install-debian13.sh on $(date)
TERMINAL_TID=$TERMINAL_TID

# Test Mode (set to false for production)
TEST_MODE=false

# Network Configuration
PORT=8082
LOCAL_PORT=5000
TERMINAL_PORT=5010

# Backend URL (VPN)
BACKEND_URL=http://100.64.0.7:3000

# Timeouts (milliseconds)
PAYMENT_TIMEOUT=60000
BIND_TIMEOUT=10000

# Terminal IP Address (auto-detected via broadcast, can override if needed)
TERMINAL_IP=10.42.0.75

# Device Manager
DEVICE_MANAGER_URL=http://100.64.0.7:8090
DEVICE_ID=$DEVICE_HOSTNAME
EOF
    
    chown $DEVICE_USER:$DEVICE_USER "$TERMINAL_DIR/.env"
    log "✓ .env configured with TID: $TERMINAL_TID"
    
    # Skip creating placeholder files - we have real ones from GitHub
    # Original placeholder code removed - now using full PeP implementation
    
    # REMOVED: Create simplified server.js (will need full PeP protocol files from admin1)
    # NOW: Using full server.js from GitHub with PeP protocol
    
    : <<'TERM_EOF'
    # This placeholder code is no longer needed - kept as comment for reference
const express = require('express');
const cors = require('cors');

const app = express();
const PORT = process.env.PORT || 8082;

app.use(cors());
app.use(express.json({ limit: '10mb' }));

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ 
    status: 'ok', 
    service: 'payment-terminal',
    message: 'Terminal service installed - requires PeP protocol configuration'
  });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Payment terminal service running on http://0.0.0.0:${PORT}`);
  console.log('NOTE: This is a placeholder - copy full service from admin1');
});
TERM_EOF
    
    # Placeholder code above is kept as comment only
    # heartbeat.js, package.json, .env.template already exist from GitHub
    
    log "Skipping placeholder file creation - using files from GitHub"
    
    # REMOVED: Create heartbeat.js (already in GitHub)
    : <<'HEARTBEAT_EOF'
const axios = require('axios');
const os = require('os');

const DEVICE_MANAGER_URL = process.env.DEVICE_MANAGER_URL || 'http://100.64.0.7:8090';
const DEVICE_ID = process.env.DEVICE_ID || os.hostname();
const HEARTBEAT_INTERVAL = parseInt(process.env.HEARTBEAT_INTERVAL || '30000');

function getVpnIP() {
  try {
    const interfaces = os.networkInterfaces();
    if (interfaces['tailscale0']) {
      const ipv4 = interfaces['tailscale0'].find(i => i.family === 'IPv4');
      if (ipv4) return ipv4.address;
    }
    return null;
  } catch (err) {
    console.error('[Terminal Heartbeat] Error getting VPN IP:', err.message);
    return null;
  }
}

async function sendHeartbeat() {
  try {
    const vpnIP = getVpnIP();
    if (!vpnIP) {
      console.warn('[Terminal Heartbeat] Skipping - no VPN IP');
      return;
    }
    
    const payload = {
      deviceId: DEVICE_ID,
      ip: vpnIP,
      hostname: os.hostname(),
      type: 'payment-terminal',
      capabilities: {
        paymentTerminal: true,
        terminalPort: 8082,
        terminalTID: process.env.TERMINAL_TID || 'unknown'
      },
      status: 'online',
      timestamp: new Date().toISOString()
    };
    
    const response = await axios.post(
      `${DEVICE_MANAGER_URL}/heartbeat`,
      payload,
      { timeout: 5000 }
    );
    
    console.log(`[Terminal Heartbeat] ✓ Sent: ${DEVICE_ID} @ ${vpnIP}`, response.status);
  } catch (err) {
    console.error('[Terminal Heartbeat] ✗ Error:', err.message);
  }
}

console.log(`[Terminal Heartbeat] Starting for device: ${DEVICE_ID}`);
console.log(`[Terminal Heartbeat] Device Manager: ${DEVICE_MANAGER_URL}`);

sendHeartbeat();
const intervalId = setInterval(sendHeartbeat, HEARTBEAT_INTERVAL);

process.on('SIGTERM', () => {
  console.log('[Terminal Heartbeat] Stopping...');
  clearInterval(intervalId);
});

module.exports = { sendHeartbeat, getVpnIP };
HEARTBEAT_EOF
    
    # REMOVED: Create .env template (already in GitHub)
    chown -R $DEVICE_USER:$DEVICE_USER "$TERMINAL_DIR"
    
    log "Installing npm dependencies..."
    if ! su - $DEVICE_USER -c "cd $TERMINAL_DIR && npm install --silent" 2>&1 | tee -a "$LOG_FILE"; then
        log_warning "npm install failed with --silent, trying verbose..."
        if ! su - $DEVICE_USER -c "cd $TERMINAL_DIR && npm install" 2>&1 | tee -a "$LOG_FILE"; then
            log_error "Failed to install npm dependencies"
            return 1
        fi
    fi
    
    if [ ! -d "$TERMINAL_DIR/node_modules" ]; then
        log_error "npm install completed but node_modules not found"
        return 1
    fi
    
    log "Creating systemd service for terminal API..."
    cat > /etc/systemd/system/gastro-terminal.service <<EOF2
[Unit]
Description=Gastro Payment Terminal Service
After=network.target tailscaled.service

[Service]
Type=simple
User=$DEVICE_USER
WorkingDirectory=$TERMINAL_DIR
EnvironmentFile=$TERMINAL_DIR/.env
Environment="DEVICE_ID=$DEVICE_HOSTNAME"
Environment="DEVICE_MANAGER_URL=http://100.64.0.7:8090"
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF2
    
    log "Creating systemd service for terminal heartbeat..."
    cat > /etc/systemd/system/gastro-terminal-heartbeat.service <<EOF3
[Unit]
Description=Gastro Payment Terminal Heartbeat
After=network.target tailscaled.service gastro-terminal.service

[Service]
Type=simple
User=$DEVICE_USER
WorkingDirectory=$TERMINAL_DIR
EnvironmentFile=$TERMINAL_DIR/.env
Environment="DEVICE_ID=$DEVICE_HOSTNAME"
Environment="DEVICE_MANAGER_URL=http://100.64.0.7:8090"
ExecStart=/usr/bin/node heartbeat.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF3
    
    systemctl daemon-reload
    systemctl enable gastro-terminal.service
    systemctl enable gastro-terminal-heartbeat.service
    
    if ! systemctl start gastro-terminal.service 2>&1 | tee -a "$LOG_FILE"; then
        log_error "Failed to start gastro-terminal.service"
        log_error "Check logs: journalctl -u gastro-terminal.service -n 50"
        return 1
    fi
    
    if ! systemctl start gastro-terminal-heartbeat.service 2>&1 | tee -a "$LOG_FILE"; then
        log_error "Failed to start gastro-terminal-heartbeat.service"
        log_error "Check logs: journalctl -u gastro-terminal-heartbeat.service -n 50"
        return 1
    fi
    
    log "Terminal service installed and started"
    log "Testing terminal service..."
    sleep 3
    
    if curl -s http://localhost:8082/health | grep -q '"status":"ok"'; then
        log "✓ Terminal service health check passed"
        log_info "Terminal configured with TID=$TERMINAL_TID"
        log_info "Terminal will auto-detect IP via broadcast"
    else
        log_warning "⚠ Terminal service health check failed - service may not be ready yet"
        log_warning "Check logs: journalctl -u gastro-terminal.service -f"
    fi
    
    log "Phase 7 completed successfully"
}

phase8_cleanup() {
    print_header "PHASE 8: CLEANUP & OPTIMIZATION"
    
    log "Cleaning apt cache..."
    apt-get autoremove -y -qq
    apt-get clean
    
    log "Setting proper permissions..."
    chown -R $DEVICE_USER:$DEVICE_USER /home/$DEVICE_USER
    
    log "Phase 8 completed successfully"
}

phase9_validation() {
    print_header "PHASE 9: VALIDATION"
    
    log "Running system validation checks..."
    
    local errors=0
    local warnings=0
    
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
    if command -v chromium &>/dev/null; then
        log "✓ Chromium is installed"
        local version=$(chromium --version 2>&1 | head -1)
        log_info "  Version: $version"
    else
        log_error "✗ Chromium not found"
        ((errors++))
    fi
    
    # Check VPN
    if command -v tailscale &>/dev/null; then
        log "✓ Tailscale is installed"
        if systemctl is-enabled tailscaled &>/dev/null; then
            log "✓ Tailscaled service is enabled"
        else
            log_warning "⚠ Tailscaled service is not enabled"
            ((warnings++))
        fi
    else
        log_error "✗ Tailscale not found"
        ((errors++))
    fi
    
    # Check startup script
    if [ -f "/usr/local/bin/gastro-kiosk-start.sh" ]; then
        log "✓ Startup script exists"
        if [ -x "/usr/local/bin/gastro-kiosk-start.sh" ]; then
            log "✓ Startup script is executable"
        else
            log_error "✗ Startup script is not executable"
            ((errors++))
        fi
    else
        log_error "✗ Startup script not found"
        ((errors++))
    fi
    
    # Check autostart
    if [ -f "/home/$DEVICE_USER/.config/autostart/gastro-kiosk.desktop" ]; then
        log "✓ Autostart desktop file exists"
    else
        log_error "✗ Autostart desktop file not found"
        ((errors++))
    fi
    
    # Check printer service (if installed)
    if systemctl list-unit-files | grep -q "gastro-printer.service"; then
        log "✓ Printer service is installed"
        if systemctl is-enabled gastro-printer.service &>/dev/null; then
            log "✓ Printer service is enabled"
            if systemctl is-active gastro-printer.service &>/dev/null; then
                log "✓ Printer service is running"
            else
                log_warning "⚠ Printer service is not running"
                ((warnings++))
            fi
        else
            log_warning "⚠ Printer service is not enabled"
            ((warnings++))
        fi
    else
        log_info "ℹ Printer service not installed (optional)"
    fi
    
    # Check terminal service (if installed)
    if systemctl list-unit-files | grep -q "gastro-terminal.service"; then
        log "✓ Terminal service is installed"
        if systemctl is-enabled gastro-terminal.service &>/dev/null; then
            log "✓ Terminal service is enabled"
            if systemctl is-active gastro-terminal.service &>/dev/null; then
                log "✓ Terminal service is running"
            else
                log_warning "⚠ Terminal service is not running"
                ((warnings++))
            fi
        else
            log_warning "⚠ Terminal service is not enabled"
            ((warnings++))
        fi
    else
        log_info "ℹ Terminal service not installed (optional)"
    fi
    
    # Check Python dependencies
    if command -v python3 &>/dev/null; then
        log "✓ Python3 is installed: $(python3 --version 2>&1)"
    else
        log_error "✗ Python3 not found"
        ((errors++))
    fi
    
    # Summary
    echo ""
    log "========================================="
    log "VALIDATION SUMMARY"
    log "========================================="
    
    if [[ $errors -eq 0 ]]; then
        log "✓ All critical checks passed!"
    else
        log_error "✗ Found $errors critical error(s)"
    fi
    
    if [[ $warnings -gt 0 ]]; then
        log_warning "⚠ Found $warnings warning(s)"
    fi
    
    if [[ $errors -gt 0 ]]; then
        log_error "Installation completed with errors. Please review the logs."
        log_error "Log file: $LOG_FILE"
        return 1
    else
        log "Installation validation successful!"
        return 0
    fi
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    print_header "GASTRO KIOSK PRO - DEBIAN 13 INSTALLER v3.0"
    
    # Pre-flight checks
    check_root
    check_debian
    
    # Configuration
    prompt_configuration
    
    # Installation phases
    phase1_system_preparation
    phase2_lightdm_openbox
    phase3_chromium
    phase4_vpn
    
    # Auto-detect hardware before installation
    detect_printer
    detect_terminal
    
    phase5_kiosk_service
    phase6_printer_service
    phase7_terminal_service
    phase8_cleanup
    
    # Validation
    if ! phase9_validation; then
        log_error "Validation failed. Please check the errors above."
        log_error "You can review the full log at: $LOG_FILE"
        echo ""
        read -p "Continue with reboot anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Installation aborted by user"
            exit 1
        fi
    fi
    
    # Final summary
    print_header "INSTALLATION COMPLETE"
    
    log "========================================="
    log "INSTALLATION SUMMARY"
    log "========================================="
    log "Hostname: $DEVICE_HOSTNAME"
    log "Role: $DEVICE_ROLE"
    log "User: $DEVICE_USER"
    log "URL: https://${SERVER_IP}:${SERVER_PORT}?deviceId=${DEVICE_HOSTNAME}"
    log ""
    log "Display Manager: LightDM (Openbox/X11)"
    log "Browser: Chromium (native Debian package)"
    log "VPN: Tailscale/Headscale"
    log ""
    log "Log file: $LOG_FILE"
    log "========================================="
    log ""
    log "The system will reboot in 10 seconds..."
    log "After reboot, the kiosk will start automatically"
    log ""
    log "Press Ctrl+C to cancel reboot"
    
    sleep 10
    
    log "Rebooting now..."
    reboot
}

# Execute main function
main
