const axios = require('axios');
const os = require('os');

const DEVICE_MANAGER_URL = process.env.DEVICE_MANAGER_URL || 'http://100.64.0.4:8090';
const DEVICE_ID = process.env.DEVICE_ID || os.hostname();
const HEARTBEAT_INTERVAL = parseInt(process.env.HEARTBEAT_INTERVAL || '30000');

function getVpnIP() {
  try {
    const interfaces = os.networkInterfaces();
    if (interfaces['tailscale0']) {
      const ipv4 = interfaces['tailscale0'].find(i => i.family === 'IPv4');
      if (ipv4) return ipv4.address;
    }
    console.warn('[Terminal Heartbeat] No VPN interface found');
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
console.log(`[Terminal Heartbeat] Interval: ${HEARTBEAT_INTERVAL}ms`);

sendHeartbeat();
const intervalId = setInterval(sendHeartbeat, HEARTBEAT_INTERVAL);

process.on('SIGTERM', () => {
  console.log('[Terminal Heartbeat] Stopping...');
  clearInterval(intervalId);
});

process.on('SIGINT', () => {
  console.log('[Terminal Heartbeat] Stopping...');
  clearInterval(intervalId);
  process.exit(0);
});

module.exports = { sendHeartbeat, getVpnIP };