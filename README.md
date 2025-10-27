# DevOps Stage 2 - Blue/Green Deployment with Auto-Failover

A production-ready Blue/Green deployment setup using Nginx with automatic failover capabilities.

Overview

This project implements a Blue/Green deployment strategy where:
- **Blue** is the primary (active) service
- **Green** is the backup (standby) service
- **Nginx** automatically switches to backup on primary failure
- Zero client-facing errors during failover

## 🏗️ Architecture

```
                    ┌──────────────────┐
                    │  Nginx Proxy     │
                    │  :8080           │
                    └────────┬─────────┘
                             │
                    ┌────────┴─────────┐
                    │                  │
            ┌───────▼──────┐   ┌──────▼────────┐
            │  Blue App    │   │  Green App    │
            │  :8081       │   │  :8082        │
            │  (Primary)   │   │  (Backup)     │
            └──────────────┘   └───────────────┘
```

Prerequisites

- Docker (v20.10+)
- Docker Compose (v2.0+)
- curl (for testing)

## 🚀 Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/akaprogressuche/Test-Application
cd stage2-devops
```

### 2. Configure Environment Variables

Copy the example environment file:

```bash
cp .env.example .env
```

Edit `.env` with your configuration:

```env
BLUE_IMAGE=your-registry/nodejs-app:blue
GREEN_IMAGE=your-registry/nodejs-app:green
ACTIVE_POOL=blue
RELEASE_ID_BLUE=blue-v1.0.0
RELEASE_ID_GREEN=green-v1.0.0
```

### 3. Start the Services

```bash
docker-compose up -d
```

### 4. Verify Deployment

```bash
# Check all services are running
docker-compose ps

# Test the application
curl http://localhost:8080/version
```

Expected response:
```json
{
  "version": "1.0.0",
  "pool": "blue"
}
```

Check headers:
```bash
curl -I http://localhost:8080/version
```

Should include:
```
X-App-Pool: blue
X-Release-Id: blue-v1.0.0
```

## Testing Failover

### Test Automatic Failover

1. **Induce failure on Blue:**
```bash
# Simulate 500 errors
curl -X POST http://localhost:8081/chaos/start?mode=error

# OR simulate timeouts
curl -X POST http://localhost:8081/chaos/start?mode=timeout
```

2. **Verify automatic switch to Green:**
```bash
# Send multiple requests
for i in {1..10}; do
  curl -s http://localhost:8080/version | jq '.pool'
done
```

Output should show:
```
"green"
"green"
"green"
...
```

3. **Check headers:**
```bash
curl -I http://localhost:8080/version | grep X-App-Pool
```

Should show:
```
X-App-Pool: green
```

4. **Restore Blue:**
```bash
curl -X POST http://localhost:8081/chaos/stop
```

### Monitor During Failover

```bash
# Watch responses in real-time
watch -n 0.5 'curl -s http://localhost:8080/version'

# Check Nginx logs
docker-compose logs -f nginx
```

## 🔧 Configuration

### Environment Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `BLUE_IMAGE` | Docker image for Blue service | - | Yes |
| `GREEN_IMAGE` | Docker image for Green service | - | Yes |
| `ACTIVE_POOL` | Active pool (blue/green) | blue | Yes |
| `RELEASE_ID_BLUE` | Blue release identifier | - | Yes |
| `RELEASE_ID_GREEN` | Green release identifier | - | Yes |
| `PORT` | Internal container port | 3000 | No |
| `NGINX_PORT` | Nginx public port | 8080 | No |
| `BLUE_PORT` | Blue direct access port | 8081 | No |
| `GREEN_PORT` | Green direct access port | 8082 | No |

### Nginx Failover Parameters

Key configuration in `nginx.conf.template`:

```nginx
upstream backend {
    server app_blue:3000 max_fails=2 fail_timeout=5s;
    server app_green:3000 backup;
}

# Tight timeouts for fast detection
proxy_connect_timeout 2s;
proxy_read_timeout 2s;

# Retry on errors
proxy_next_upstream error timeout http_500 http_502 http_503 http_504;
proxy_next_upstream_tries 2;
```

**Parameters Explained:**
- `max_fails=2`: Mark server down after 2 failures
- `fail_timeout=5s`: Consider server failed for 5 seconds
- `backup`: Only use when primary fails
- `proxy_connect_timeout=2s`: Max 2s to establish connection
- `proxy_read_timeout=2s`: Max 2s to read response
- `proxy_next_upstream_tries=2`: Retry up to 2 times

## 📊 Available Endpoints

### Via Nginx (Port 8080)

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/version` | GET | Get app version and pool info |
| `/healthz` | GET | Health check endpoint |
| `/chaos/start` | POST | Start chaos simulation |
| `/chaos/stop` | POST | Stop chaos simulation |

### Direct Access

| Service | Port | URL |
|---------|------|-----|
| Blue | 8081 | http://localhost:8081 |
| Green | 8082 | http://localhost:8082 |
| Nginx | 8080 | http://localhost:8080 |

## 🧹 Management Commands

### View Logs

```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f nginx
docker-compose logs -f app_blue
docker-compose logs -f app_green
```

### Restart Services

```bash
# All services
docker-compose restart

# Specific service
docker-compose restart nginx
docker-compose restart app_blue
```

### Reload Nginx (without downtime)

```bash
docker-compose exec nginx nginx -s reload
```

### Stop All Services

```bash
docker-compose down
```

### Clean Up Everything

```bash
docker-compose down -v
docker system prune -a
```

Troubleshooting

### Problem: Services won't start

**Solution:**
```bash
# Check container logs
docker-compose logs

# Verify images exist
docker images | grep nodejs-app

# Check port conflicts
netstat -tulpn | grep -E '8080|8081|8082'
```

### Problem: Failover not working

**Solution:**
```bash
# Check Nginx upstream status
docker-compose exec nginx cat /var/log/nginx/error.log

# Verify health checks
curl http://localhost:8081/healthz
curl http://localhost:8082/healthz

# Test direct access to services
curl http://localhost:8081/version
curl http://localhost:8082/version
```

### Problem: Headers not forwarding

**Solution:**
```bash
# Check Nginx config
docker-compose exec nginx cat /etc/nginx/nginx.conf

# Verify proxy_pass_header is set
docker-compose exec nginx nginx -T | grep proxy_pass_header

# Test direct to app
curl -I http://localhost:8081/version
```

## 📈 Performance Tuning

### Adjust Failover Speed

Edit `nginx.conf.template`:

```nginx
# Faster failover (more aggressive)
proxy_connect_timeout 1s;
proxy_read_timeout 1s;
max_fails=1;
fail_timeout=3s;

# Slower failover (more tolerant)
proxy_connect_timeout 5s;
proxy_read_timeout 5s;
max_fails=3;
fail_timeout=10s;
```

### Increase Connection Pool

```nginx
upstream backend {
    server app_blue:3000;
    server app_green:3000 backup;
    keepalive 64;  # Increase from 32
}
```

## 🔐 Security Considerations

1. **Network Isolation**: Services communicate via internal Docker network
2. **Health Check Access**: Limited to internal network only
3. **Direct Port Access**: Should be restricted in production (8081, 8082)
4. **Header Validation**: Consider validating upstream headers

## 🏆 Success Criteria

- ✅ All requests return 200 OK in normal state
- ✅ Zero failed requests during Blue failure
- ✅ Automatic switch to Green within 2-5 seconds
- ✅ Correct headers (X-App-Pool, X-Release-Id) before and after failover
- ✅ ≥95% of responses from Green after Blue fails

## 📝 Testing Script

Automated test script:

```bash
#!/bin/bash

echo "=== Blue/Green Deployment Test ==="

# Test 1: Normal state
echo "Test 1: Verify Blue is active"
for i in {1..5}; do
    curl -s http://localhost:8080/version | jq -r '.pool'
done

# Test 2: Induce failure
echo -e "\nTest 2: Inducing failure on Blue"
curl -X POST http://localhost:8081/chaos/start?mode=error

sleep 2

# Test 3: Verify failover
echo -e "\nTest 3: Verify automatic failover to Green"
success=0
for i in {1..20}; do
    response=$(curl -s http://localhost:8080/version)
    pool=$(echo $response | jq -r '.pool')
    echo "Request $i: $pool"
    if [ "$pool" == "green" ]; then
        ((success++))
    fi
    sleep 0.5
done

echo -e "\nSuccess rate: $((success * 100 / 20))%"

# Test 4: Restore
echo -e "\nTest 4: Restoring Blue"
curl -X POST http://localhost:8081/chaos/stop

echo -e "\n=== Test Complete ==="
```

Save as `test.sh`, then run:
```bash
chmod +x test.sh
./test.sh
```

