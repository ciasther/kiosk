# PRINTER ROUTING FIX - COMPLETE SOLUTION

## ROOT CAUSE IDENTIFIED ✅

**Problem**: All customer kiosks were printing to admin1's printer (100.64.0.6:8081), regardless of which device placed the order.

**Root Causes**:
1. **Nginx Hardcoded Proxy** (8443 → admin1:8081)
   - File: `/etc/nginx/conf.d/gastro.conf` in gastro_nginx container
   - All requests to `https://192.168.31.139:8443` were proxied to `http://192.168.31.205:8081`

2. **Frontend Hardcoded URL**
   - File: `kiosk-client-frontend/.env`
   - `VITE_PRINTER_URL=https://192.168.31.139:8443` (pointing to nginx proxy)
   - ALL kiosks used the same hardcoded URL

3. **Backend Missing Device-Specific Routing**
   - File: `backend/src/services/deviceService.js`
   - `getPrinterUrl()` returned first available printer, not device-specific

## SOLUTION IMPLEMENTED ✅

### 1. Backend API - Device-Specific Routing

**File**: `backend/src/services/deviceService.js`
- Added `getDeviceById(deviceId)` method
- Updated `getPrinterUrl(deviceId)` to accept optional deviceId parameter
- If deviceId provided → query device-manager for that specific device
- If no deviceId → fallback to first available printer

**File**: `backend/src/routes/printer.js`
- Accept deviceId from request body OR x-device-id header
- Pass deviceId to `deviceService.getPrinterUrl(deviceId)`
- Route to device-specific printer URL

### 2. Frontend - Use Backend API

**File**: `kiosk-client-frontend/src/services/printer.ts`
- Changed from direct printer call to backend API call
- Call `/api/printer/print-ticket` with orderId + deviceId
- Backend handles routing to correct device's printer

**File**: `kiosk-client-frontend/src/services/api.ts`
- Already had interceptor adding x-device-id header from localStorage

### 3. Bug Fixes

**File**: `backend/src/routes/printer.js`
- Fixed Prisma query: `include: { items: ... }` → `include: { orderItems: ... }`
- Fixed data access: `order.items` → `order.orderItems`

## FLOW AFTER FIX ✅

### Scenario 1: Order from kiosk@100.64.0.11
1. User places order on kiosk@100.64.0.11
2. Frontend saves deviceId to localStorage: `kiosk-0216`
3. Order confirmation page calls: `printTicket(order)`
4. API request: `POST /api/printer/print-ticket` with `x-device-id: kiosk-0216`
5. Backend: `deviceService.getPrinterUrl('kiosk-0216')`
6. Device-manager returns: `{ ip: "100.64.0.11", printerPort: 8083 }`
7. Backend calls: `http://100.64.0.11:8083/print/ticket`
8. ✅ Ticket prints on kiosk's LOCAL printer

### Scenario 2: Order from admin1@100.64.0.6
1. User places order on admin1@100.64.0.6
2. Frontend saves deviceId to localStorage: `admin1-RB102`
3. Order confirmation page calls: `printTicket(order)`
4. API request: `POST /api/printer/print-ticket` with `x-device-id: admin1-RB102`
5. Backend: `deviceService.getPrinterUrl('admin1-RB102')`
6. Device-manager returns: `{ ip: "100.64.0.6", printerPort: 8081 }`
7. Backend calls: `http://100.64.0.6:8081/print/ticket`
8. ✅ Ticket prints on admin1's LOCAL printer

## TESTING RESULTS ✅

```bash
# Test 1: Backend routing with kiosk-0216
curl -X POST http://100.64.0.7:3000/api/printer/print-ticket \
  -H "x-device-id: kiosk-0216" \
  -d '{"orderId": "test"}'
# Result: [Printer] Print request - orderId: test, deviceId: kiosk-0216

# Test 2: Backend routing with admin1-RB102
curl -X POST http://100.64.0.7:3000/api/printer/print-ticket \
  -H "x-device-id: admin1-RB102" \
  -d '{"orderId": "test"}'
# Result: [Printer] Print request - orderId: test, deviceId: admin1-RB102

# Test 3: Device-specific printer URL resolution
curl "http://100.64.0.7:3000/api/printer/health?deviceId=kiosk-0216"
# Result: {"printerUrl":"http://100.64.0.11:8083",...}

curl "http://100.64.0.7:3000/api/printer/health?deviceId=admin1-RB102"
# Result: {"printerUrl":"http://100.64.0.6:8081",...}
```

## FILES MODIFIED ✅

### Backend (kiosk-server)
- `/home/kiosk-server/gastro-kiosk-docker/backend/src/services/deviceService.js`
  - Backup: `deviceService.js.backup-before-routing-fix-20251223-*`
- `/home/kiosk-server/gastro-kiosk-docker/backend/src/routes/printer.js`
  - Backup: `printer.js.backup-before-routing-fix-20251223-*`

### Frontend (kiosk-server)
- `/home/kiosk-server/kiosk-client-frontend/src/services/printer.ts`
  - Backup: `printer.ts.backup-before-routing-fix-20251223-*`
- `/home/kiosk-server/kiosk-client-frontend/src/pages/OrderConfirmationPage.tsx`
  - Changed: `printTicket(order, i18n.language)` → `printTicket(order)`

### Deployed
- Docker container: `gastro_backend` (restarted)
- Frontend: `/home/kiosk-server/gastro-kiosk-docker/frontends/kiosk/` (rebuilt and deployed)
  - Backup: `frontends/kiosk.backup-before-routing-fix-20251223-*`

## VERIFICATION STEPS 📋

To verify the fix works with real orders:

1. **On kiosk@100.64.0.11**:
   ```bash
   # Check deviceId is set
   # Open browser DevTools → Application → localStorage
   # Should have: kiosk_device_id = "kiosk-0216"
   
   # Place a real order (CASH payment)
   # On order confirmation → ticket should print on LOCAL printer (100.64.0.11)
   ```

2. **On admin1@100.64.0.6**:
   ```bash
   # Check deviceId is set
   # Should have: kiosk_device_id = "admin1-RB102"
   
   # Place a real order (CASH payment)
   # On order confirmation → ticket should print on LOCAL printer (100.64.0.6)
   ```

3. **Check backend logs**:
   ```bash
   ssh kiosk-server@100.64.0.7
   docker logs gastro_backend -f | grep -E 'Printer|DeviceService'
   
   # Should see:
   # [Printer] Print request - orderId: xxx, deviceId: kiosk-0216
   # [DeviceService] Getting printer URL for specific device: kiosk-0216
   # [DeviceService] Using device-specific printer: http://100.64.0.11:8083
   ```

## BENEFITS ✅

1. **Plug-and-Play**: New devices with printers automatically work
2. **VPN-Compatible**: Works across different local networks
3. **Centralized Logic**: Backend controls routing, easy to debug
4. **No Hardcoding**: Device-specific URLs resolved dynamically
5. **Fallback**: If no deviceId, uses any available printer

## REMAINING WORK ⚠️

The nginx proxy on port 8443 is still configured but NO LONGER USED by the new frontend.
You can optionally remove it from `/etc/nginx/conf.d/gastro.conf` in the future.

## VERSION UPDATE

Update `AGENTS.md` with:
- Version: v3.0.11-printer-routing-fix
- Date: 2025-12-23
- Status: ✅ TESTED - Ready for production verification
