/**
 * Payment Terminal Service - PeP Protocol Implementation
 * Real UDP communication with Polskie ePłatności terminal
 */

const express = require('express');
const cors = require('cors');
const fs = require('fs');
const path = require('path');
const { TerminalClient } = require('./src/terminal/client');

const app = express();
const PORT = process.env.PORT || 8082;

app.use(cors());
app.use(express.json({ limit: '10mb' }));

// Terminal client instance
let terminalClient = null;
let backendUrl = process.env.BACKEND_URL || 'http://192.168.31.139:3000';

// Configuration
const config = {
  tid: process.env.TERMINAL_TID || '00000000', // MUST BE SET!
  testMode: process.env.TEST_MODE === 'true',
  localPort: parseInt(process.env.LOCAL_PORT || '5000'),
  terminalPort: parseInt(process.env.TERMINAL_PORT || '5010'),
};

// Logging
const logDir = path.join(__dirname, 'logs');
if (!fs.existsSync(logDir)) {
  fs.mkdirSync(logDir, { recursive: true });
}

const logFile = path.join(logDir, 'payment-terminal.log');
const log = (message) => {
  const timestamp = new Date().toISOString();
  const logMessage = `[${timestamp}] ${message}\n`;
  console.log(logMessage.trim());
  try {
    fs.appendFileSync(logFile, logMessage);
  } catch (err) {
    console.error('Failed to write log:', err);
  }
};

// Initialize terminal client
async function initTerminal() {
  try {
    log('Initializing PeP Terminal Client...');
    
    terminalClient = new TerminalClient({
      terminalTID: config.tid,
      localPort: config.localPort,
      terminalPort: config.terminalPort, testMode: config.testMode,
      bindTimeout: parseInt(process.env.BIND_TIMEOUT || '10000'),
    });
    
    await terminalClient.init();
    log('UDP socket initialized');
    
    // Terminal events
    terminalClient.on('progress', async (data) => {
      log(`Payment progress: ${data.status} (code: ${data.code})`);
      await notifyBackend('progress', data);
    });
    
    terminalClient.on('result', async (data) => {
      log(`Payment result: ${data.success ? 'SUCCESS' : 'FAILED'} (code: ${data.code})`);
      await notifyBackend('result', data);
    });
    
    terminalClient.on('cancelled', async (data) => {
      log(`Payment cancelled: ${data.id}`);
      await notifyBackend('cancelled', data);
    });
    
    terminalClient.on('error', (err) => {
      log(`Terminal error: ${err.message}`);
    });
    
    terminalClient.on('bound', (data) => {
      log(`Terminal bound: TID ${data.tid} at ${data.ip}`);
    });
    
    // Bind terminal on startup
    if (config.tid && config.tid !== '00000000') {
      log(`Attempting to bind terminal with TID: ${config.tid}`);
      try {
        await terminalClient.bindTerminal(config.tid);
        log('Terminal binding successful!');
      } catch (err) {
        log(`Terminal binding failed: ${err.message}`);
        log('Terminal will need to be bound manually via /terminal/bind endpoint');
      }
    } else {
      log('WARNING: No valid TID configured. Set TERMINAL_TID in .env');
      log('Terminal binding skipped - use /terminal/bind endpoint to bind manually');
    }
    
  } catch (err) {
    log(`Failed to initialize terminal client: ${err.message}`);
    throw err;
  }
}

// Notify backend about payment events
async function notifyBackend(event, data) {
  const axios = require('axios');
  
  try {
    const payload = {
      event,
      data,
      timestamp: new Date().toISOString(),
    };
    
    log(`Notifying backend: ${event}`);
    
    const response = await axios.post(`${backendUrl}/api/payment/callback`, payload, {
      timeout: 5000,
      headers: {
        'Content-Type': 'application/json',
      }
    });
    
    log(`Backend notified successfully: ${response.status}`);
  } catch (err) {
    log(`Failed to notify backend: ${err.message}`);
    // Don't throw - continue processing
  }
}

// Routes

// Health check
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    service: 'payment-terminal-pep',
    provider: 'Polskie ePlatnosci',
    terminalReady: terminalClient?.ready || false,
    terminalBound: !!terminalClient?.terminalIP,
    terminalIP: terminalClient?.terminalIP || null,
    terminalTID: terminalClient?.terminalTID || null,
    testMode: config.testMode,
    timestamp: new Date().toISOString(),
  });
});

// Terminal status
app.get('/status', (req, res) => {
  if (!terminalClient) {
    return res.status(503).json({ 
      error: 'Terminal client not initialized',
      ready: false,
    });
  }
  
  res.json({
    ready: terminalClient.ready,
    bound: !!terminalClient.terminalIP,
    ip: terminalClient.terminalIP,
    tid: terminalClient.terminalTID,
    currentTransaction: terminalClient.currentTransaction,
    config: {
      localPort: config.localPort,
      terminalPort: config.terminalPort, testMode: config.testMode,
      bindTimeout: parseInt(process.env.BIND_TIMEOUT || '10000'),
      testMode: config.testMode,
    }
  });
});

// Terminal status (alias for compatibility)
app.get('/terminal/status', (req, res) => {
  if (!terminalClient) {
    return res.status(503).json({ 
      error: 'Terminal client not initialized',
      connected: false,
    });
  }
  
  res.json({
    connected: !!terminalClient.terminalIP,
    terminalId: terminalClient.terminalTID || 'NOT_BOUND',
    terminalIP: terminalClient.terminalIP || null,
    provider: 'Polskie ePlatnosci',
    protocol: 'UDP/PEP',
    lastCheck: new Date().toISOString()
  });
});

// Bind terminal (manual rebind if needed)
app.post('/terminal/bind', async (req, res) => {
  const { tid } = req.body;
  
  if (!tid || tid.length !== 8) {
    return res.status(400).json({ 
      error: 'Invalid TID (must be 8 digits)',
      example: '12345678'
    });
  }
  
  if (!terminalClient) {
    return res.status(503).json({ error: 'Terminal client not initialized' });
  }
  
  try {
    log(`Manual terminal binding requested for TID: ${tid}`);
    const result = await terminalClient.bindTerminal(tid);
    log(`Terminal bound successfully: ${result.ip}`);
    res.json({
      success: true,
      ...result,
    });
  } catch (err) {
    log(`Terminal binding failed: ${err.message}`);
    res.status(500).json({ 
      error: err.message,
      tip: 'Check if terminal is on, connected to network, and configured for UDP/PEP mode'
    });
  }
});

// Start payment
app.post('/payment/start', async (req, res) => {
  const { orderId, amount, operatorCode, description } = req.body;
  
  if (!amount || amount <= 0) {
    return res.status(400).json({ error: 'Invalid amount (must be > 0)' });
  }
  
  if (!orderId) {
    return res.status(400).json({ error: 'Missing orderId' });
  }
  
  if (!terminalClient) {
    return res.status(503).json({ error: 'Terminal client not initialized' });
  }
  
  if (!terminalClient.terminalIP) {
    return res.status(503).json({ 
      error: 'Terminal not connected',
      tip: 'Use POST /terminal/bind with your terminal TID to bind terminal first'
    });
  }
  
  try {
    const transactionId = orderId; // orderId is already TXN- from backend
    
    log(`Starting payment: Order ${orderId}, Amount ${amount} PLN, Transaction ${transactionId}`);
    
    await terminalClient.sendPayment({
      amount: parseFloat(amount),
      transactionId,
      operatorCode: operatorCode || '0001',
      description: description || `Order #${orderId}`,
    });
    
    log('Payment request sent to terminal');
    
    res.json({
      success: true,
      status: 'initiated',
      transactionId,
      amount: parseFloat(amount),
      message: 'Payment initiated on terminal. Please follow terminal instructions.',
    });
  } catch (err) {
    log(`Payment initiation failed: ${err.message}`);
    res.status(500).json({ 
      error: err.message,
      details: 'Failed to send payment request to terminal'
    });
  }
});

// Cancel payment
app.post('/payment/cancel', async (req, res) => {
  const { transactionId } = req.body;
  
  if (!transactionId) {
    return res.status(400).json({ error: 'Missing transactionId' });
  }
  
  if (!terminalClient) {
    return res.status(503).json({ error: 'Terminal client not initialized' });
  }
  
  try {
    log(`Cancelling payment: ${transactionId}`);
    await terminalClient.cancelTransaction();
    
    res.json({
      success: true,
      status: 'cancelled',
      transactionId,
    });
  } catch (err) {
    log(`Payment cancellation failed: ${err.message}`);
    res.status(500).json({ error: err.message });
  }
});

// Get payment status
app.get('/payment/status/:transactionId', (req, res) => {
  if (!terminalClient) {
    return res.status(503).json({ error: 'Terminal client not initialized' });
  }
  
  const tx = terminalClient.currentTransaction;
  
  if (!tx || !tx.id || !tx.id.includes(req.params.transactionId)) {
    return res.status(404).json({ 
      error: 'Transaction not found',
      transactionId: req.params.transactionId
    });
  }
  
  res.json({
    transaction: tx,
    status: tx.status,
  });
});

// Test endpoint (for development)
app.post('/payment/test', async (req, res) => {
  if (!config.testMode) {
    return res.status(403).json({ error: 'Test mode not enabled' });
  }
  
  log('Test payment requested');
  
  res.json({
    success: true,
    message: 'Test payment created',
    transactionId: 'TEST-' + Date.now(),
    note: 'This is a test transaction (TEST_MODE=true)'
  });
});

// Get all transactions (debug)
app.get('/transactions', (req, res) => {
  if (!terminalClient) {
    return res.json({ transactions: [] });
  }
  
  res.json({
    current: terminalClient.currentTransaction,
    terminalBound: !!terminalClient.terminalIP,
  });
});

// Error handler
app.use((err, req, res, next) => {
  log(`Error: ${err.message}`);
  res.status(500).json({ error: 'Internal server error', details: err.message });
});

// Start server
async function start() {
  try {
    await initTerminal();
    
    app.listen(PORT, () => {
      log(`Payment Terminal Service (PeP Protocol) running on port ${PORT}`);
      log(`Backend URL: ${backendUrl}`);
      log(`Local UDP port: ${config.localPort}`);
      log(`Terminal UDP port: ${config.terminalPort}`);
      log(`Test mode: ${config.testMode}`);
      log('Service ready!');
    });
  } catch (err) {
    log(`Failed to start service: ${err.message}`);
    process.exit(1);
  }
}

// Graceful shutdown
process.on('SIGINT', () => {
  log('Shutting down...');
  if (terminalClient) {
    terminalClient.close();
  }
  process.exit(0);
});

process.on('SIGTERM', () => {
  log('Shutting down...');
  if (terminalClient) {
    terminalClient.close();
  }
  process.exit(0);
});

start();

// Start heartbeat
try {
  require('./heartbeat');
  console.log('[Payment Terminal] Heartbeat module loaded');
} catch (err) {
  console.warn('[Payment Terminal] Heartbeat not available:', err.message);
}
