/**
 * TLV (Tag-Length-Value) Encoding/Decoding for PeP Protocol
 * FIXED: Proper BCD encoding for numeric fields (n4, n6, n8, etc.)
 */

/**
 * Encode numeric value as BCD (Binary Coded Decimal) in HEX ASCII
 * @param {string|number} value - Numeric value
 * @param {number} digits - Number of BCD digits (e.g., 4 for n4)
 * @returns {string} - BCD encoded as HEX ASCII string
 */
function encodeBCD(value, digits) {
  // Convert to string and pad with zeros
  const numStr = value.toString().padStart(digits, '0');
  
  // BCD encoding: each byte holds 2 decimal digits
  // Example: "0001" (4 digits) → 0x00 0x01 (2 bytes) → "0001" in hex ASCII
  // The value "0001" already represents the hex! So we just ensure proper length
  
  // Each 2 digits = 1 byte in BCD
  // So n4 (4 digits) = 2 bytes, n6 = 3 bytes, n8 = 4 bytes
  const bytes = Math.ceil(digits / 2);
  
  // Pad to even number of digits for BCD
  const paddedStr = numStr.padStart(bytes * 2, '0');
  
  return paddedStr.toUpperCase();
}

/**
 * Calculate byte length for BCD encoded value
 * @param {number} digits - Number of decimal digits
 * @returns {number} - Number of bytes needed
 */
function bcdByteLength(digits) {
  return Math.ceil(digits / 2);
}

/**
 * Build TLV field with proper encoding
 * @param {string} tag - Tag (e.g., 'DF01')
 * @param {string} value - Value (will be BCD encoded if numeric)
 * @param {string} format - Format hint: 'n4', 'n6', 'an42', etc. (optional)
 * @returns {string} - TLV encoded string
 */
function buildTLV(tag, value, format = null) {
  let encodedValue = value;
  let length = value.length;
  
  // If format is specified and starts with 'n', encode as BCD
  if (format && format.match(/^n(\d+)$/)) {
    const digits = parseInt(format.match(/^n(\d+)$/)[1]);
    encodedValue = encodeBCD(value, digits);
    length = bcdByteLength(digits);
  } else if (format && format.match(/^\.\.n(\d+)$/)) {
    // Variable length numeric (..n4, ..n6)
    const maxDigits = parseInt(format.match(/^\.\.n(\d+)$/)[1]);
    const actualDigits = value.toString().length;
    encodedValue = encodeBCD(value, actualDigits);
    length = bcdByteLength(actualDigits);
  } else {
    // String/ASCII value - length is number of characters
    length = value.length;
    encodedValue = value;
  }
  
  const lengthHex = length.toString(16).padStart(2, '0').toUpperCase();
  return tag + lengthHex + encodedValue;
}

/**
 * Build TLV field - simple version (auto-detect format)
 * @param {string} tag - Tag (e.g., 'DF01')
 * @param {string|number} value - Value
 * @returns {string} - TLV encoded string
 */
function buildTLVSimple(tag, value) {
  // Known tags with BCD encoding
  const bcdTags = {
    'DF01': 4,  // Transaction type: n4
    'DF03': 6,  // STAN: n6
    'DF05': 4,  // Operator code: n4
  };
  
  if (bcdTags[tag]) {
    return buildTLV(tag, value, `n${bcdTags[tag]}`);
  }
  
  // Default: treat as string
  const length = value.toString().length.toString(16).padStart(2, '0').toUpperCase();
  return tag + length + value.toString();
}

/**
 * Parse TLV data
 * @param {string} data - TLV encoded data
 * @returns {Object} - Parsed fields
 */
function parseTLV(data) {
  const fields = {};
  let pos = 0;
  
  while (pos < data.length) {
    if (pos + 4 > data.length) break;
    
    const tag = data.substr(pos, 4);
    pos += 4;
    
    if (pos + 2 > data.length) break;
    const length = parseInt(data.substr(pos, 2), 16);
    pos += 2;
    
    if (pos + length * 2 > data.length) break; // length is in bytes, but data is hex ASCII (2 chars per byte)
    const value = data.substr(pos, length * 2);
    pos += length * 2;
    
    fields[tag] = value;
  }
  
  return fields;
}

/**
 * Encode amount in grosze (cents) with '!' prefix to prevent editing
 * Format: b5 = 5 bytes binary = 10 hex chars
 * @param {number} amount - Amount in PLN (e.g., 10.50)
 * @returns {string} - Encoded amount (e.g., '!00010000' as 8 BCD digits = 4 bytes)
 */
function encodeAmount(amount) {
  const grosze = Math.round(amount * 100);
  // Amount is n12 format (12 decimal digits) but can be prefixed with '!'
  // With '!', it's 1 byte (0x21) + 12 BCD digits (6 bytes) = 7 bytes total
  // But in ASCII hex: "21" + 12 hex digits = 14 characters
  const bcdAmount = grosze.toString().padStart(12, '0');
  return '21' + bcdAmount; // 0x21 = '!' in ASCII
}

/**
 * Decode amount from grosze
 * @param {string} encoded - Encoded amount
 * @returns {number} - Amount in PLN
 */
function decodeAmount(encoded) {
  // Remove '!' prefix (0x21 in hex = "21")
  let clean = encoded;
  if (clean.startsWith('21')) {
    clean = clean.substr(2);
  }
  // Remove leading zeros
  clean = clean.replace(/^0+/, '') || '0';
  return parseInt(clean, 10) / 100;
}

module.exports = {
  buildTLV,
  buildTLVSimple,
  parseTLV,
  encodeAmount,
  decodeAmount,
  encodeBCD,
  bcdByteLength,
};
