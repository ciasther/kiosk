#!/bin/bash
# Quick test script to verify install script is ready for demo
# FIXED VERSION: Correct ports, VPN IP, device-manager test, Headscale test

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# FIXED: Use VPN IP for external network testing
SERVER_IP_LOCAL="192.168.31.139"  # Local network
SERVER_IP_VPN="100.64.0.7"         # VPN (Headscale/Tailscale)
SERVER_IP_EXTERNAL="89.72.39.90"   # External IP

# Try VPN first, fallback to local
if ping -c 1 -W 2 $SERVER_IP_VPN &> /dev/null; then
  SERVER_IP=$SERVER_IP_VPN
  NETWORK_TYPE="VPN"
elif ping -c 1 -W 2 $SERVER_IP_LOCAL &> /dev/null; then
  SERVER_IP=$SERVER_IP_LOCAL
  NETWORK_TYPE="Local"
else
  echo -e "${RED}ERROR: Server not reachable on VPN or local network!${NC}"
  exit 1
fi

ERRORS=0

echo "========================================="
echo "  Install Script Pre-Demo Verification"
echo "  Network: $NETWORK_TYPE ($SERVER_IP)"
echo "========================================="
echo ""

# Test 1: Server reachability (already done above)
echo -e "Test 1: Ping server... ${GREEN}✓ PASS ($NETWORK_TYPE)${NC}"

# Test 2: HTTP server for install script hosting
echo -n "Test 2: HTTP server (port 8000)... "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://$SERVER_IP:8000/ 2>&1)
if [ "$HTTP_CODE" = "200" ]; then
  echo -e "${GREEN}✓ PASS (HTTP $HTTP_CODE)${NC}"
else
  echo -e "${RED}✗ FAIL (HTTP $HTTP_CODE)${NC}"
  echo -e "${YELLOW}  Hint: Run 'python3 -m http.server 8000' in scripts folder${NC}"
  ((ERRORS++))
fi

# Test 3: Install script availability (check both names)
echo -n "Test 3: Install script... "
for SCRIPT_NAME in "kiosk-install-FIXED-v2.sh" "install-full-device.sh" "kiosk-install.sh"; do
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://$SERVER_IP:8000/$SCRIPT_NAME 2>&1)
  if [ "$HTTP_CODE" = "200" ]; then
    SIZE=$(curl -sI http://$SERVER_IP:8000/$SCRIPT_NAME 2>/dev/null | grep -i content-length | awk '{print $2}' | tr -d '\r')
    if [ -n "$SIZE" ] && [ "$SIZE" -gt 10000 ]; then
      echo -e "${GREEN}✓ PASS ($SCRIPT_NAME - ${SIZE} bytes)${NC}"
      SCRIPT_FOUND=true
      break
    fi
  fi
done

if [ "$SCRIPT_FOUND" != "true" ]; then
  echo -e "${RED}✗ FAIL (no valid install script found)${NC}"
  ((ERRORS++))
fi

# Test 4: payment-terminal-service.tar.gz
echo -n "Test 4: payment-terminal-service.tar.gz... "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://$SERVER_IP:8000/payment-terminal-service.tar.gz 2>&1)
if [ "$HTTP_CODE" = "200" ]; then
  SIZE=$(curl -sI http://$SERVER_IP:8000/payment-terminal-service.tar.gz 2>/dev/null | grep -i content-length | awk '{print $2}' | tr -d '\r')
  if [ -n "$SIZE" ]; then
    SIZE_MB=$((SIZE / 1024 / 1024))
    echo -e "${GREEN}✓ PASS (${SIZE_MB}MB)${NC}"
  else
    echo -e "${GREEN}✓ PASS${NC}"
  fi
else
  echo -e "${YELLOW}⚠ WARNING (HTTP $HTTP_CODE) - Optional${NC}"
fi

# Test 5: Backend API
echo -n "Test 5: Backend API (3000)... "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://$SERVER_IP:3000/health 2>&1)
if [ "$HTTP_CODE" = "200" ]; then
  echo -e "${GREEN}✓ PASS${NC}"
else
  echo -e "${RED}✗ FAIL (HTTP $HTTP_CODE)${NC}"
  ((ERRORS++))
fi

# Test 6: Device Manager (ADDED!)
echo -n "Test 6: Device Manager (8090)... "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://$SERVER_IP:8090/health 2>&1)
if [ "$HTTP_CODE" = "200" ]; then
  echo -e "${GREEN}✓ PASS${NC}"
else
  echo -e "${RED}✗ FAIL (HTTP $HTTP_CODE)${NC}"
  echo -e "${YELLOW}  Hint: Device-manager is CRITICAL for terminal/printer detection!${NC}"
  ((ERRORS++))
fi

# Test 7-9: HTTPS apps with CORRECT PORTS (FIXED!)
echo -n "Test 7: Kiosk app (3001)... "
HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" https://$SERVER_IP:3001/ 2>&1)
if [ "$HTTP_CODE" = "200" ]; then
  echo -e "${GREEN}✓ PASS (Customer ordering)${NC}"
else
  echo -e "${RED}✗ FAIL (HTTP $HTTP_CODE)${NC}"
  ((ERRORS++))
fi

echo -n "Test 8: Display app (3002)... "
HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" https://$SERVER_IP:3002/ 2>&1)
if [ "$HTTP_CODE" = "200" ]; then
  echo -e "${GREEN}✓ PASS (Order status)${NC}"
else
  echo -e "${RED}✗ FAIL (HTTP $HTTP_CODE)${NC}"
  ((ERRORS++))
fi

echo -n "Test 9: Cashier app (3003)... "
HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" https://$SERVER_IP:3003/ 2>&1)
if [ "$HTTP_CODE" = "200" ]; then
  echo -e "${GREEN}✓ PASS (Kitchen/Admin)${NC}"
else
  echo -e "${RED}✗ FAIL (HTTP $HTTP_CODE)${NC}"
  ((ERRORS++))
fi

# Test 10: Headscale server (ADDED!)
echo -n "Test 10: Headscale server... "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://$SERVER_IP_EXTERNAL:32654/ 2>&1)
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "404" ] || [ "$HTTP_CODE" = "301" ]; then
  echo -e "${GREEN}✓ PASS (reachable)${NC}"
else
  echo -e "${YELLOW}⚠ WARNING (HTTP $HTTP_CODE)${NC}"
  echo -e "${YELLOW}  Hint: Check if Headscale is running${NC}"
fi

# Test 11: Docker containers (if we have access)
echo -n "Test 11: Docker containers... "
if command -v sshpass &> /dev/null; then
  CONTAINERS=$(sshpass -p '1234' ssh -o StrictHostKeyChecking=no kiosk-server@$SERVER_IP_LOCAL "docker compose -f ~/gastro-kiosk-docker/docker-compose.yml ps --format json 2>/dev/null | wc -l" 2>/dev/null || echo "0")
  if [ "$CONTAINERS" -gt 0 ]; then
    echo -e "${GREEN}✓ PASS ($CONTAINERS containers)${NC}"
  else
    echo -e "${YELLOW}⚠ SKIP (no SSH access)${NC}"
  fi
else
  echo -e "${YELLOW}⚠ SKIP (sshpass not installed)${NC}"
fi

# Test 12: Payment terminal (optional)
echo -n "Test 12: Payment terminal (10.42.0.75)... "
if ping -c 1 -W 1 10.42.0.75 &> /dev/null; then
  echo -e "${GREEN}✓ DETECTED${NC}"
else
  echo -e "${YELLOW}○ NOT DETECTED (optional)${NC}"
fi

# Summary
echo ""
echo "========================================="
echo "  Port Mapping Verification:"
echo "========================================="
echo "  :3001 → Kiosk (Customer ordering)"
echo "  :3002 → Display (Order status)"
echo "  :3003 → Cashier (Kitchen/Admin)"
echo "  :3000 → Backend API"
echo "  :8090 → Device Manager"
echo ""

if [ $ERRORS -eq 0 ]; then
  echo "========================================="
  echo -e "${GREEN}  ✓ ALL TESTS PASSED!${NC}"
  echo -e "${GREEN}  System is READY for demo!${NC}"
  echo "========================================="
  echo ""
  echo "Installation command for new devices:"
  if [ "$NETWORK_TYPE" = "VPN" ]; then
    echo "  wget -O - http://100.64.0.7:8000/kiosk-install-FIXED-v2.sh | sudo bash"
  else
    echo "  wget -O - http://192.168.31.139:8000/kiosk-install-FIXED-v2.sh | sudo bash"
  fi
  echo ""
  echo "Or with role selection:"
  echo "  wget http://$SERVER_IP:8000/kiosk-install-FIXED-v2.sh"
  echo "  sudo bash kiosk-install-FIXED-v2.sh [kiosk|cashier|display]"
  exit 0
else
  echo "========================================="
  echo -e "${RED}  ✗ $ERRORS TEST(S) FAILED!${NC}"
  echo -e "${RED}  System is NOT ready for demo!${NC}"
  echo "========================================="
  echo ""
  echo "Please fix the failing tests before demo."
  exit 1
fi
