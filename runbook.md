# DevOps Runbook - Blue/Green Deployment Alerts

# Overview
This runbook describes alert types from the Blue/Green deployment monitoring system and appropriate operator responses.

---

## Alert Types

### Failover Detected

**What it means:**  
Traffic has automatically switched from one pool to another (e.g., Blue → Green or Green → Blue). This indicates the primary pool is unhealthy and the system has failed over to the backup pool.

**Alert Example:**
```
Failover detected: blue → green
Primary pool (blue) is likely unhealthy. Traffic is now being served by green.
```

**Operator Actions:**

1. **Acknowledge the alert** - Confirm you've received it
2. **Check the failed pool's health:**
   ```bash
   docker compose logs blue
   # or
   docker compose logs green
   ```
3. **Inspect container status:**
   ```bash
   docker compose ps
   ```
4. **Review Nginx error logs:**
   ```bash
   docker compose exec nginx cat /var/log/nginx/error.log
   ```
5. **Investigate root cause:**
   - Application crash?
   - Resource exhaustion (CPU/memory)?
   - Configuration issue?
   - Network connectivity problem?

6. **Recovery steps:**
   - Fix the underlying issue
   - Restart the failed container:
     ```bash
     docker compose restart blue
     ```
   - Verify health endpoint returns 200
   - Monitor for stability

7. **Optional: Manual failback**
   - Once primary is stable, update `.env`:
     ```bash
     ACTIVE_POOL=blue
     ```
   - Reload Nginx:
     ```bash
     docker compose exec nginx nginx -s reload
     ```

**Escalation:** If failover happens repeatedly (>3 times in 1 hour), escalate to senior engineer.

---

### High Error Rate

**What it means:**  
The upstream services are returning 5xx errors above the configured threshold (default: 2% over last 200 requests). This indicates backend services are degraded or failing.

**Alert Example:**
```
High error rate detected: 5.50% (11/200 requests)
Threshold: 2%
Window size: 200 requests
```

**Operator Actions:**

1. **Acknowledge the alert**
2. **Check current error rate:**
   ```bash
   docker compose logs alert_watcher --tail=50
   ```
3. **Inspect both pool logs:**
   ```bash
   docker compose logs blue --tail=100
   docker compose logs green --tail=100
   ```
4. **Check Nginx access logs for patterns:**
   ```bash
   docker compose exec nginx tail -n 100 /var/log/nginx/access.log
   ```
5. **Identify failing endpoints:**
   - Which routes are returning 5xx?
   - Is it all traffic or specific paths?
   - Check request patterns

6. **Diagnose root cause:**
   - Database connectivity issues?
   - Dependency service down?
   - Resource exhaustion?
   - Code bug in recent deployment?

7. **Mitigation options:**
   - **Toggle to healthier pool:**
     ```bash
     # If blue is having issues, switch to green
     echo "ACTIVE_POOL=green" >> .env
     docker compose up -d nginx
     ```
   - **Roll back deployment** if issue started after recent deploy
   - **Scale resources** if CPU/memory constrained
   - **Restart affected containers:**
     ```bash
     docker compose restart blue green
     ```

8. **Monitor recovery:**
   - Watch error rate decrease in logs
   - Verify error rate falls below threshold

**Escalation:** If error rate stays above 10% for >5 minutes, escalate immediately.

---

### ✅ Recovery Detected

**What it means:**  
The system has returned to normal operation. The primary pool is healthy again and serving traffic.

**Operator Actions:**

1. **Verify stability:**
   - Monitor for 15-30 minutes
   - Ensure no new alerts trigger
2. **Document the incident:**
   - What caused the issue?
   - How long was the outage?
   - What fixed it?
3. **Update postmortem (if applicable)**

---

## Maintenance Mode

### Suppressing Alerts During Planned Changes

When performing planned maintenance (deployments, config changes, etc.), you may want to temporarily suppress alerts:

**Option 1: Stop the watcher**
```bash
docker compose stop alert_watcher
# Perform maintenance
docker compose start alert_watcher
```

**Option 2: Set a high cooldown**
```bash
# In .env
ALERT_COOLDOWN_SEC=3600  # 1 hour
docker compose up -d alert_watcher
```

**Option 3: Remove Slack webhook temporarily**
```bash
# Comment out in .env
# SLACK_WEBHOOK_URL=https://...
docker compose up -d alert_watcher
```

---

## Testing Alerts

### Test Failover Alert
```bash
# Stop primary pool
docker compose stop blue

# Generate traffic
for i in {1..50}; do curl http://localhost:8080/; done

# You should see a failover alert in Slack
```

### Test Error Rate Alert
```bash
# If your app has an error endpoint
for i in {1..100}; do curl http://localhost:8080/error; done

# Or stop both pools briefly
docker compose stop blue green
for i in {1..100}; do curl http://localhost:8080/; done
docker compose start blue green
```

---

## Useful Commands

### View Live Nginx Logs
```bash
docker compose exec nginx tail -f /var/log/nginx/access.log
```

### View Watcher Logs
```bash
docker compose logs -f alert_watcher
```

### Check Current Active Pool
```bash
grep ACTIVE_POOL .env
```

### Manually Switch Pools
```bash
# Switch to green
sed -i 's/ACTIVE_POOL=.*/ACTIVE_POOL=green/' .env
docker compose up -d nginx

# Switch to blue
sed -i 's/ACTIVE_POOL=.*/ACTIVE_POOL=blue/' .env
docker compose up -d nginx
```

### View Container Health
```bash
docker compose ps
docker stats --no-stream
```

---

