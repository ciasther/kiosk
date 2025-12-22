#!/bin/bash
# GASTRO KIOSK - FIXED INSTALLER v2 (DEMO-READY)
# Fixes: Port mapping, IP addresses, device-manager, onboard keyboard, heartbeat
# Usage from external network: 
#   wget -O - http://89.72.39.90:32654/install-fixed.sh | sudo bash
# Or save and run:
#   wget http://89.72.39.90:32654/install-fixed.sh
#   sudo bash install-fixed.sh

set -e

# Configuration
SERVER_IP="100.64.0.7"  # VPN IP (Tailscale/Headscale) - FIXED!
SERVER_IP_EXTERNAL="89.72.39.90"  # External IP for Headscale
USE_TAILSCALE=true
HEADSCALE_URL="http://89.72.39.90:32654"
HEADSCALE_KEY="cfb43efbf5b0bf89d2949ce4dd1ccc644e3e987e45ca5e80"
DEVICE_MANAGER_URL="http://100.64.0.7:8090"  # ADDED!

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================="
echo "  Gastro Kiosk - FIXED Installer v2"
echo "  Server: $SERVER_IP"
echo "  Device Manager: $DEVICE_MANAGER_URL"
echo "========================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
   echo -e "${RED}ERROR: Please run as root (use sudo)${NC}"
   exit 1
fi

# Detect actual user (not root)
if [ -n "$SUDO_USER" ]; then
  ACTUAL_USER=$SUDO_USER
else
  ACTUAL_USER=$(logname 2>/dev/null || echo $USER)
fi

echo -e "${GREEN}>>> Detected user: $ACTUAL_USER${NC}"

# Interactive role selection if not provided
if [ -z "$1" ]; then
  echo ""
  echo "Select device role:"
  echo "  1) Kiosk (Customer ordering)"
  echo "  2) Cashier (Kitchen/Admin panel)"
  echo "  3) Display (Order status screen)"
  echo ""
  read -p "Enter choice [1-3]: " ROLE_CHOICE
  
  case $ROLE_CHOICE in
    1) ROLE="kiosk" ;;
    2) ROLE="cashier" ;;
    3) ROLE="display" ;;
    *) 
      echo -e "${RED}Invalid choice${NC}"
      exit 1
      ;;
  esac
else
  ROLE=$1
fi

echo -e "${GREEN}>>> Selected role: $ROLE${NC}"
echo ""

# 1. Install Base Dependencies + Onboard Keyboard
echo -e "${YELLOW}>>> Step 1/6: Installing base dependencies...${NC}"
apt-get update -qq
apt-get install -y curl wget unzip chromium-browser zenity x11-xserver-utils unclutter \
  onboard nodejs npm > /dev/null 2>&1

echo -e "${GREEN}✓ Base dependencies installed (including onboard keyboard)${NC}"

# 2. Optional: Tailscale VPN with validation
if [ "$USE_TAILSCALE" = true ] && [ -n "$HEADSCALE_URL" ]; then
  echo -e "${YELLOW}>>> Step 2/6: Installing Tailscale VPN...${NC}"
  if ! command -v tailscale &> /dev/null; then
    curl -fsSL https://tailscale.com/install.sh | sh > /dev/null 2>&1
  fi
  
  echo "Connecting to VPN..."
  if tailscale up --login-server=$HEADSCALE_URL --authkey=$HEADSCALE_KEY --accept-routes 2>&1 | tee /tmp/tailscale.log | grep -q "Success\|Logged in"; then
    echo -e "${GREEN}✓ Tailscale connected${NC}"
    
    # Wait for VPN to stabilize
    echo "Waiting for VPN to stabilize..."
    for i in {1..10}; do
      if tailscale status 2>/dev/null | grep -q "$SERVER_IP"; then
        echo -e "${GREEN}✓ VPN stable, server reachable${NC}"
        break
      fi
      sleep 2
    done
  else
    echo -e "${RED}✗ Tailscale connection failed!${NC}"
    echo -e "${YELLOW}  Please check authkey or connection${NC}"
    echo -e "${YELLOW}  Install log: /tmp/tailscale.log${NC}"
    read -p "Continue anyway (local network only)? [y/N]: " CONTINUE
    if [[ ! $CONTINUE =~ ^[Yy]$ ]]; then
      exit 1
    fi
  fi
else
  echo -e "${YELLOW}>>> Step 2/6: Skipping Tailscale (using local network)${NC}"
fi

# 3. Detect and Setup Printer (Only for cashier role)
echo -e "${YELLOW}>>> Step 3/6: Checking for printer...${NC}"
PRINTER_FOUND=false

if [ "$ROLE" = "cashier" ]; then
  if lsusb | grep -iE "printer|thermal|escpos|hwasung" > /dev/null; then
    echo -e "${GREEN}✓ Printer detected!${NC}"
    PRINTER_FOUND=true
    
    if [ ! -d "/opt/gastro-printer-service" ]; then
      echo "  Installing printer service..."
      
      mkdir -p /opt/gastro-printer-service
      cat > /opt/gastro-printer-service/package.json << 'EOF'
{
  "name": "gastro-printer-service",
  "version": "1.0.0",
  "main": "index.js",
  "dependencies": {
    "express": "^4.18.0",
    "escpos": "^3.0.0-alpha.6",
    "escpos-usb": "^3.0.0-alpha.4",
    "cors": "^2.8.5",
    "axios": "^1.6.0"
  }
}
EOF

      cat > /opt/gastro-printer-service/index.js << 'EOF'
const express = require('express');
const escpos = require('escpos');
const usb = escpos.USB;
const cors = require('cors');
const axios = require('axios');
const os = require('os');

const app = express();
app.use(express.json());
app.use(cors());

const DEVICE_MANAGER_URL = process.env.DEVICE_MANAGER_URL || 'http://100.64.0.7:8090';
const DEVICE_ID = process.env.DEVICE_ID || os.hostname();

let device;
try {
  device = new usb();
  console.log('[Printer] USB device initialized');
} catch (e) {
  console.error('[Printer] No USB printer found:', e.message);
}

// Send heartbeat every 30s
const sendHeartbeat = async () => {
  try {
    await axios.post(`${DEVICE_MANAGER_URL}/heartbeat`, {
      deviceId: DEVICE_ID,
      capabilities: {
        printer: device ? true : false
      },
      timestamp: new Date().toISOString()
    });
    console.log('[Heartbeat] Sent to device-manager');
  } catch (error) {
    console.error('[Heartbeat] Failed:', error.message);
  }
};

// Initial heartbeat
sendHeartbeat();

// Periodic heartbeat every 30s
setInterval(sendHeartbeat, 30000);

app.get('/health', (req, res) => {
  res.json({ 
    status: 'ok', 
    printer: device ? 'connected' : 'not found',
    deviceId: DEVICE_ID,
    deviceManager: DEVICE_MANAGER_URL
  });
});

app.post('/print', async (req, res) => {
  if (!device) {
    return res.status(503).json({ error: 'Printer not available' });
  }

  try {
    const { order } = req.body;
    const printer = new escpos.Printer(device);

    device.open(function(error){
      if (error) {
        return res.status(500).json({ error: error.message });
      }

      printer
        .font('a')
        .align('ct')
        .style('bu')
        .size(2, 2)
        .text('Gastro Kiosk')
        .size(1, 1)
        .text('------------------------')
        .text('Order #' + order.orderNumber)
        .text('------------------------')
        .align('lt');

      order.items.forEach(item => {
        printer.text(item.quantity + 'x ' + item.name);
      });

      printer
        .text('------------------------')
        .text('Total: ' + order.totalAmount + ' PLN')
        .text('Payment: ' + order.paymentMethod)
        .text('------------------------')
        .text('Thank you!')
        .cut()
        .close();

      res.json({ success: true });
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

const PORT = 8081;
app.listen(PORT, () => {
  console.log(`Printer service running on port ${PORT}`);
  console.log(`Device ID: ${DEVICE_ID}`);
  console.log(`Device Manager: ${DEVICE_MANAGER_URL}`);
});
EOF

      cd /opt/gastro-printer-service
      npm install --silent > /dev/null 2>&1

      # FIXED: Added DEVICE_MANAGER_URL and DEVICE_ID environment variables
      cat > /etc/systemd/system/gastro-printer.service << EOF
[Unit]
Description=Gastro Kiosk Printer Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/gastro-printer-service
Environment="DEVICE_MANAGER_URL=$DEVICE_MANAGER_URL"
Environment="DEVICE_ID=$(hostname)"
ExecStart=/usr/bin/node /opt/gastro-printer-service/index.js
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

      systemctl daemon-reload
      systemctl enable gastro-printer.service > /dev/null 2>&1
      systemctl start gastro-printer.service
      
      echo -e "${GREEN}  ✓ Printer service installed with heartbeat${NC}"
    else
      echo -e "${GREEN}  ✓ Printer service already installed${NC}"
    fi
  else
    echo -e "${YELLOW}  ⚠ No printer detected${NC}"
  fi
else
  echo -e "${YELLOW}  ⚠ Skipping printer (not cashier role)${NC}"
fi

# 4. Detect and Setup Payment Terminal (Only for cashier role)
echo -e "${YELLOW}>>> Step 4/6: Checking for payment terminal...${NC}"
TERMINAL_FOUND=false

if [ "$ROLE" = "cashier" ]; then
  if ping -c 1 -W 1 10.42.0.75 &> /dev/null; then
    echo -e "${GREEN}✓ Payment terminal detected at 10.42.0.75${NC}"
    TERMINAL_FOUND=true
    
    if [ ! -d "/home/$ACTUAL_USER/payment-terminal-service" ]; then
      echo "  Installing payment terminal service..."
      
      # Download from server if available (use external IP for initial download, then VPN IP after connected)
      DOWNLOAD_IP=$SERVER_IP_EXTERNAL
      if [ "$(tailscale status 2>/dev/null | grep -c '$SERVER_IP')" -gt 0 ]; then
        DOWNLOAD_IP=$SERVER_IP
      fi
      
      if curl -f -s http://$DOWNLOAD_IP:8000/payment-terminal-service.tar.gz -o /tmp/payment-terminal.tar.gz; then
        mkdir -p /home/$ACTUAL_USER/payment-terminal-service
        cd /home/$ACTUAL_USER/payment-terminal-service
        tar xzf /tmp/payment-terminal.tar.gz
        chown -R $ACTUAL_USER:$ACTUAL_USER /home/$ACTUAL_USER/payment-terminal-service
        
        # Install dependencies
        sudo -u $ACTUAL_USER npm install --silent > /dev/null 2>&1

        # Create .env if not exists - FIXED: BACKEND_URL uses correct IP
        if [ ! -f .env ]; then
          cat > .env << 'ENVFILE'
TERMINAL_TID=01100460
TEST_MODE=false
PORT=8082
LOCAL_PORT=5000
TERMINAL_PORT=5010
BACKEND_URL=http://100.64.0.7:3000
PAYMENT_TIMEOUT=60000
BIND_TIMEOUT=10000
TERMINAL_IP=10.42.0.75
ENVFILE
          chown $ACTUAL_USER:$ACTUAL_USER .env
        fi

        # FIXED: Added DEVICE_MANAGER_URL and DEVICE_ID environment variables
        cat > /etc/systemd/system/payment-terminal.service << EOF
[Unit]
Description=PeP Payment Terminal Service - Real UDP Protocol
After=network.target

[Service]
Type=simple
User=$ACTUAL_USER
WorkingDirectory=/home/$ACTUAL_USER/payment-terminal-service
Environment="DEVICE_MANAGER_URL=$DEVICE_MANAGER_URL"
Environment="DEVICE_ID=$(hostname)"
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=3
StandardOutput=append:/home/$ACTUAL_USER/payment-terminal-service/logs/service.log
StandardError=append:/home/$ACTUAL_USER/payment-terminal-service/logs/service.log

[Install]
WantedBy=multi-user.target
EOF

        systemctl daemon-reload
        systemctl enable payment-terminal.service > /dev/null 2>&1
        systemctl start payment-terminal.service
        
        echo -e "${GREEN}  ✓ Payment terminal service installed${NC}"
      else
        echo -e "${YELLOW}  ⚠ Could not download payment service from server${NC}"
      fi
    else
      echo -e "${GREEN}  ✓ Payment terminal service already installed${NC}"
    fi
  else
    echo -e "${YELLOW}  ⚠ No payment terminal detected${NC}"
  fi
else
  echo -e "${YELLOW}  ⚠ Skipping payment terminal (not cashier role)${NC}"
fi

# 5. Determine App URL based on role - FIXED PORT MAPPING!
echo -e "${YELLOW}>>> Step 5/6: Configuring application...${NC}"
case $ROLE in
  kiosk)
    APP_URL="https://$SERVER_IP:3001"  # FIXED: Customer ordering (was :3002)
    APP_NAME="Kiosk (Customer)"
    ;;
  cashier)
    APP_URL="https://$SERVER_IP:3003"  # OK: Kitchen/Admin
    APP_NAME="Cashier/Kitchen"
    ;;
  display)
    APP_URL="https://$SERVER_IP:3002"  # FIXED: Order status (was :3001)
    APP_NAME="Display (Status)"
    ;;
esac

echo -e "${GREEN}  App URL: $APP_URL${NC}"

# 6. Setup Auto-start Script & Desktop Launcher + Onboard Keyboard
echo -e "${YELLOW}>>> Step 6/6: Setting up auto-start...${NC}"

# Setup Onboard keyboard autostart
mkdir -p /home/$ACTUAL_USER/.config/autostart
cat > /home/$ACTUAL_USER/.config/autostart/onboard.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Onboard
Exec=onboard --xid
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF
chown -R $ACTUAL_USER:$ACTUAL_USER /home/$ACTUAL_USER/.config/autostart

echo -e "${GREEN}  ✓ Onboard keyboard configured${NC}"

# Create start script with improved VPN check and chromium flags
cat > /usr/local/bin/gastro-kiosk-start.sh << EOF
#!/bin/bash
# Disable screen blanking
xset s off
xset -dpms
xset s noblank

# Hide cursor
unclutter -idle 0.1 &

# Wait for network and VPN connection - FIXED: Check for correct IP
echo "Waiting for VPN connection..."
for i in {1..30}; do
  if tailscale status 2>/dev/null | grep -q "$SERVER_IP"; then
    echo "VPN connected to $SERVER_IP!"
    break
  fi
  sleep 2
done

# Additional wait for stability
sleep 3

# Start Chromium in kiosk mode - FIXED: Added touch events and temp profile
chromium-browser \\
  --kiosk \\
  --touch-events=enabled \\
  --user-data-dir=/tmp/chromium-kiosk-\$\$ \\
  --noerrdialogs \\
  --disable-infobars \\
  --incognito \\
  --ignore-certificate-errors \\
  --disable-session-crashed-bubble \\
  --disable-restore-session-state \\
  --no-first-run \\
  --disable-features=TranslateUI \\
  --disable-popup-blocking \\
  "$APP_URL?deviceId=\$(hostname)"
EOF
chmod +x /usr/local/bin/gastro-kiosk-start.sh

# Create systemd service for auto-start
cat > /etc/systemd/system/gastro-kiosk.service << EOF
[Unit]
Description=Gastro Kiosk Auto-start ($APP_NAME)
After=graphical.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$ACTUAL_USER
Environment=DISPLAY=:0
Environment=XAUTHORITY=/home/$ACTUAL_USER/.Xauthority
ExecStart=/usr/local/bin/gastro-kiosk-start.sh
Restart=always
RestartSec=5

[Install]
WantedBy=graphical.target
EOF

systemctl daemon-reload
systemctl enable gastro-kiosk.service > /dev/null 2>&1

# Create manual launcher with dynamic server IP - FIXED: Correct port mapping
cat > /usr/local/bin/gastro-launcher.sh << EOF
#!/bin/bash
SERVER_IP="$SERVER_IP"

CHOICE=\$(zenity --list --title="Gastro Kiosk Launcher" \\
  --width=400 --height=300 \\
  --column="Select Mode" \\
  "Kiosk Mode (Customer)" \\
  "Cashier Mode (Kitchen)" \\
  "Display Mode (Status)" \\
  "Exit to Desktop")

case \$CHOICE in
  "Kiosk Mode (Customer)")
    chromium-browser --kiosk --touch-events=enabled --noerrdialogs --disable-infobars --incognito --ignore-certificate-errors "https://\$SERVER_IP:3001?deviceId=\$(hostname)" &
    ;;
  "Cashier Mode (Kitchen)")
    chromium-browser --kiosk --touch-events=enabled --noerrdialogs --disable-infobars --incognito --ignore-certificate-errors "https://\$SERVER_IP:3003?deviceId=\$(hostname)" &
    ;;
  "Display Mode (Status)")
    chromium-browser --kiosk --touch-events=enabled --noerrdialogs --disable-infobars --incognito --ignore-certificate-errors "https://\$SERVER_IP:3002?deviceId=\$(hostname)" &
    ;;
esac
EOF
chmod +x /usr/local/bin/gastro-launcher.sh

# Create desktop shortcut
mkdir -p /home/$ACTUAL_USER/Desktop
cat > /home/$ACTUAL_USER/Desktop/GastroKiosk.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Gastro Kiosk
Exec=/usr/local/bin/gastro-launcher.sh
Icon=system-run
Terminal=false
Categories=Application;
EOF
chown $ACTUAL_USER:$ACTUAL_USER /home/$ACTUAL_USER/Desktop/GastroKiosk.desktop
chmod +x /home/$ACTUAL_USER/Desktop/GastroKiosk.desktop

# Make desktop file trusted (Ubuntu 22.04+)
if command -v gio &> /dev/null; then
  sudo -u $ACTUAL_USER gio set /home/$ACTUAL_USER/Desktop/GastroKiosk.desktop metadata::trusted true 2>/dev/null || true
fi

echo ""
echo "========================================="
echo -e "${GREEN}  Installation Complete! ✓${NC}"
echo "========================================="
echo -e "Device Role: ${GREEN}$ROLE${NC} ($APP_NAME)"
echo "Server: $SERVER_IP"
echo "App URL: $APP_URL"
echo "Device Manager: $DEVICE_MANAGER_URL"
echo ""
echo "Hardware Detected:"
echo "  Printer: $([ "$PRINTER_FOUND" = true ] && echo -e "${GREEN}✓ YES${NC}" || echo -e "${YELLOW}✗ NO${NC}")"
echo "  Terminal: $([ "$TERMINAL_FOUND" = true ] && echo -e "${GREEN}✓ YES${NC}" || echo -e "${YELLOW}✗ NO${NC}")"
echo ""
if [ "$PRINTER_FOUND" = true ] || [ "$TERMINAL_FOUND" = true ]; then
  echo "Services:"
  [ "$PRINTER_FOUND" = true ] && echo "  • Printer: http://localhost:8081"
  [ "$TERMINAL_FOUND" = true ] && echo "  • Terminal: http://localhost:8082"
  echo ""
  echo "Device registration:"
  echo "  • Check: curl $DEVICE_MANAGER_URL/devices/\$(hostname)"
  echo ""
fi
echo "========================================="
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Reboot to start application automatically"
echo "  2. Or run manually from Desktop shortcut"
echo "  3. Or run: sudo systemctl start gastro-kiosk.service"
echo ""
echo -e "${GREEN}Ready for demo! 🚀${NC}"
echo "========================================="
