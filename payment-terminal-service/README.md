# Payment Terminal Service

PeP (Polskie ePłatności) Payment Terminal Integration Service for Gastro Kiosk Pro.

## Features

- Real UDP protocol communication with Ingenico terminals
- BCD encoding support for TLV fields
- Terminal binding and status monitoring
- Payment processing with webhook callbacks
- Heartbeat to device-manager for automatic discovery
- Test mode for development

## Installation

### Automatic (via kiosk-install-debian13.sh)

The installation script will automatically clone this service from GitHub.

### Manual

```bash
cd ~
git clone https://github.com/ciasther/kiosk.git
cp -r kiosk/payment-terminal-service ~/
cd ~/payment-terminal-service
npm install
```

## Configuration

1. Copy `.env.template` to `.env`:
   ```bash
   cp .env.template .env
   ```

2. Edit `.env` and set:
   - `TERMINAL_TID` - Your 8-digit terminal TID (check on terminal device)
   - `TERMINAL_IP` - Terminal IP address (usually 10.42.0.75)
   - `BACKEND_URL` - Backend URL (http://100.64.0.7:3000)
   - `TEST_MODE` - Set to `false` for production

3. Restart service:
   ```bash
   sudo systemctl restart gastro-terminal.service
   ```

## Files

- `server.js` - Express server with PeP protocol
- `heartbeat.js` - Device-manager registration
- `src/terminal/client.js` - UDP client for terminal communication
- `src/protocol/packet.js` - PeP packet builder/parser
- `src/protocol/tlv.js` - TLV encoding with BCD support
- `.env.template` - Configuration template

## Usage

### Start service

```bash
npm start
```

### Health check

```bash
curl http://localhost:8082/health
```

### Test mode

```bash
TEST_MODE=true npm start
```

## Troubleshooting

### Terminal not binding

1. Check terminal IP:
   ```bash
   ping 10.42.0.75
   ```

2. Check TID on terminal:
   - Menu → Zarządzanie → Wizytówka → TID (8 digits)

3. Verify `.env` configuration

### Payment timeout

- Default timeout: 60 seconds
- Adjust in `.env`: `PAYMENT_TIMEOUT=60000`

## License

ISC