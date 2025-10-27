#!/bin/bash
# Blue/Green Failover Testing Script

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
NGINX_URL="http://localhost:8080"
BLUE_URL="http://localhost:8081"
GREEN_URL="http://localhost:8082"

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Blue/Green Failover Test Suite       ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Helper functions
pass() {
    echo -e "${GREEN}✓ $1${NC}"
}

fail() {
    echo -e "${RED}✗ $1${NC}"
    exit 1
}

warn() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Test 1: Services are running
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 1: Verify all services are running"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if docker ps | grep -q "nginx_proxy"; then
    pass "Nginx is running"
else
    fail "Nginx is not running"
fi

if docker ps | grep -q "app_blue"; then
    pass "Blue app is running"
else
    fail "Blue app is not running"
fi

if docker ps | grep -q "app_green"; then
    pass "Green app is running"
else
    fail "Green app is not running"
fi

echo ""

# Test 2: Normal state - Blue is active
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 2: Verify Blue is active (normal state)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

blue_count=0
total_requests=10

for i in $(seq 1 $total_requests); do
    response=$(curl -s "${NGINX_URL}/version" || echo "")
    pool=$(echo "$response" | jq -r '.pool' 2>/dev/null || echo "unknown")
    
    if [ "$pool" == "blue" ]; then
        ((blue_count++))
    fi
    
    echo -n "."
done

echo ""

if [ $blue_count -eq $total_requests ]; then
    pass "All $total_requests requests served by Blue"
else
    fail "Only $blue_count/$total_requests requests from Blue"
fi

echo ""

# Test 3: Check headers
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 3: Verify headers are present"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

headers=$(curl -sI "${NGINX_URL}/version")

if echo "$headers" | grep -q "X-App-Pool:"; then
    pass "X-App-Pool header present"
else
    fail "X-App-Pool header missing"
fi

if echo "$headers" | grep -q "X-Release-Id:"; then
    pass "X-Release-Id header present"
else
    fail "X-Release-Id header missing"
fi

app_pool=$(echo "$headers" | grep "X-App-Pool:" | awk '{print $2}' | tr -d '\r')
if [ "$app_pool" == "blue" ]; then
    pass "X-App-Pool shows 'blue'"
else
    fail "X-App-Pool shows '$app_pool' instead of 'blue'"
fi

echo ""

# Test 4: Induce failure on Blue
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 4: Inducing failure on Blue"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

info "Triggering chaos mode on Blue..."
chaos_response=$(curl -s -X POST "${BLUE_URL}/chaos/start?mode=error" || echo "failed")

if [ "$chaos_response" != "failed" ]; then
    pass "Chaos mode activated on Blue"
else
    fail "Failed to activate chaos mode"
fi

sleep 2
echo ""

# Test 5: Verify automatic failover to Green
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 5: Verify automatic failover to Green"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

green_count=0
non_200_count=0
total_requests=20

info "Sending $total_requests requests during failover..."

for i in $(seq 1 $total_requests); do
    http_code=$(curl -s -o /dev/null -w "%{http_code}" "${NGINX_URL}/version" || echo "000")
    response=$(curl -s "${NGINX_URL}/version" || echo "")
    pool=$(echo "$response" | jq -r '.pool' 2>/dev/null || echo "unknown")
    
    if [ "$http_code" != "200" ]; then
        ((non_200_count++))
        echo -n "X"
    else
        echo -n "."
    fi
    
    if [ "$pool" == "green" ]; then
        ((green_count++))
    fi
    
    sleep 0.5
done

echo ""

# Check for zero failures
if [ $non_200_count -eq 0 ]; then
    pass "Zero failed requests during failover (${non_200_count}/${total_requests})"
else
    fail "Found ${non_200_count} failed requests (requirement: 0)"
fi

# Check if majority is from Green
green_percentage=$((green_count * 100 / total_requests))

if [ $green_percentage -ge 95 ]; then
    pass "≥95% requests from Green (${green_percentage}%)"
else
    fail "Only ${green_percentage}% from Green (requirement: ≥95%)"
fi

echo ""

# Test 6: Verify Green headers
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 6: Verify Green headers after failover"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

headers=$(curl -sI "${NGINX_URL}/version")
app_pool=$(echo "$headers" | grep "X-App-Pool:" | awk '{print $2}' | tr -d '\r')

if [ "$app_pool" == "green" ]; then
    pass "X-App-Pool correctly shows 'green'"
else
    fail "X-App-Pool shows '$app_pool' instead of 'green'"
fi

echo ""

# Test 7: Restore Blue
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 7: Restoring Blue service"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

info "Stopping chaos mode on Blue..."
restore_response=$(curl -s -X POST "${BLUE_URL}/chaos/stop" || echo "failed")

if [ "$restore_response" != "failed" ]; then
    pass "Chaos mode stopped on Blue"
else
    warn "Could not stop chaos mode (may already be stopped)"
fi

sleep 5

info "Waiting for Blue to recover..."
echo ""

# Test 8: Verify Blue recovery
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 8: Verify Blue has recovered"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

blue_recovered=0
for i in $(seq 1 5); do
    response=$(curl -s "${BLUE_URL}/version" || echo "")
    pool=$(echo "$response" | jq -r '.pool' 2>/dev/null || echo "unknown")
    
    if [ "$pool" == "blue" ]; then
        blue_recovered=1
        break
    fi
    sleep 1
done

if [ $blue_recovered -eq 1 ]; then
    pass "Blue service has recovered and responding"
else
    warn "Blue still not responding (may take longer)"
fi

echo ""

# Final Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo -e "${GREEN}✓ All critical tests passed!${NC}"
echo ""
echo "Test Results:"
echo "  • Services: All running"
echo "  • Normal state: Blue active"
echo "  • Failover: Automatic to Green"
echo "  • Zero failures: ✓"
echo "  • Green coverage: ≥95%"
echo "  • Headers: Preserved correctly"
echo ""
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Deployment Ready for Submission   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""