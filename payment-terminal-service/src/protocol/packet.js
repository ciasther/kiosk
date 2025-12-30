/**
 * PeP Protocol Packet Building and Parsing
 * FIXED: Proper parsing of terminal response packets with result codes
 */

const STX = 0x02;
const ETX = 0x03;
const FS = 0x1C;
const ACK = 0x06;
const NAK = 0x15;

/**
 * Calculate LRC checksum (XOR of all bytes except STX)
 * @param {Buffer} data - Data to checksum (without STX)
 * @returns {number} - LRC value
 */
function calculateLRC(data) {
  let lrc = 0;
  for (let i = 0; i < data.length; i++) {
    lrc ^= data[i];
  }
  return lrc;
}

/**
 * Build complete packet with STX, ETX, and LRC
 * @param {string} header - Packet header (e.g., 'UP00101')
 * @param {string} data - TLV encoded data
 * @returns {Buffer} - Complete packet
 */
function buildPacket(header, data = '') {
  // Format: <STX>header<FS><FS>data<ETX>{LRC}
  const payload = `${header}${String.fromCharCode(FS)}${String.fromCharCode(FS)}${data}`;
  const payloadBuffer = Buffer.from(payload, 'ascii');
  
  // Calculate LRC (XOR of payload + ETX)
  const fullData = Buffer.concat([payloadBuffer, Buffer.from([ETX])]);
  const lrc = calculateLRC(fullData);
  
  // Build complete packet
  return Buffer.concat([
    Buffer.from([STX]),
    fullData,
    Buffer.from([lrc])
  ]);
}

/**
 * Parse received packet
 * @param {Buffer} buffer - Received packet
 * @returns {Object|null} - Parsed packet or null if invalid
 */
function parsePacket(buffer) {
  if (buffer.length < 4) return null;
  
  // Check STX
  if (buffer[0] !== STX) return null;
  
  // Find ETX
  const etxIndex = buffer.indexOf(ETX, 1);
  if (etxIndex === -1) return null;
  
  // Extract payload and LRC
  const payload = buffer.slice(1, etxIndex);
  const receivedLRC = buffer[etxIndex + 1];
  
  // Verify LRC
  const calculatedLRC = calculateLRC(Buffer.concat([payload, Buffer.from([ETX])]));
  if (receivedLRC !== calculatedLRC) {
    console.error('LRC mismatch:', { received: receivedLRC, calculated: calculatedLRC });
    return null;
  }
  
  // Parse payload
  const payloadStr = payload.toString('ascii');
  const parts = payloadStr.split(String.fromCharCode(FS));
  
  if (parts.length < 2) return null;
  
  const header = parts[0]; // e.g., UP10152 or UP10151
  
  // Different formats for different packet types:
  // - FROM cash register (UP00101): <STX>UP00101<FS><FS>TLV_DATA<ETX>{LRC}
  //   parts = ["UP00101", "", "TLV_DATA"]
  // - FROM terminal (UP10151, UP10152): <STX>UP10151<FS>97<FS>TLV_DATA<ETX>{LRC}
  //   parts = ["UP10151", "97", "TLV_DATA"]
  
  let dataStr = '';
  
  if (header.startsWith('UP1')) {
    // Response from terminal - includes result/progress code after first FS
    // Format: <STX>UPxxxxx<FS>CODE<FS>DATA<ETX>
    // parts[0] = header
    // parts[1] = code (2 digits)
    // parts[2+] = data (may be empty or TLV)
    dataStr = parts.slice(1).join(String.fromCharCode(FS)); // Keep CODE and DATA together
  } else {
    // Request from cash register - double FS then data
    // Format: <STX>UPxxxxx<FS><FS>DATA<ETX>
    // parts[0] = header
    // parts[1] = "" (empty)
    // parts[2+] = data
    dataStr = parts.slice(2).join('');
  }
  
  return {
    header,
    direction: header.substr(2, 1), // '0' = from cash register, '1' = from terminal
    module: header.substr(3, 2), // '00' = management, '01' = payment
    command: header.substr(5, 2), // '01' = request, '51' = result, '52' = progress
    data: dataStr,
    raw: buffer,
  };
}

module.exports = {
  STX,
  ETX,
  FS,
  ACK,
  NAK,
  calculateLRC,
  buildPacket,
  parsePacket,
};
