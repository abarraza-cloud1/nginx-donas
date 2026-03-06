#!/bin/bash

echo "=== Checking Cine service status ==="
sudo systemctl status cine

echo ""
echo "=== Checking if port 3000 is listening ==="
sudo ss -tlnp | grep ':3000' || echo "Port 3000 not listening!"

echo ""
echo "=== Checking Cine service logs ==="
sudo journalctl -u cine -n 50 --no-pager

echo ""
echo "=== Testing localhost connection ==="
curl -s http://localhost:3000/ | head -20 || echo "Connection failed"

echo ""
echo "=== Checking Node.js and npm versions ==="
node --version
npm --version || echo "npm not installed"

echo ""
echo "=== Checking /opt/cine directory ==="
ls -la /opt/cine/

echo ""
echo "=== Checking /etc/cine directory ==="
ls -la /etc/cine/
cat /etc/cine/cine.env 2>/dev/null || echo "cine.env not found"
