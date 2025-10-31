import os
import time
import re
import requests
from collections import deque

# ==========================
# Configuration
# ==========================
LOG_FILE = '/var/log/nginx/access_real.log'  # ✅ FIXED: Changed from access.log
SLACK_WEBHOOK_URL = os.environ.get('SLACK_WEBHOOK_URL')
ERROR_RATE_THRESHOLD = float(os.environ.get('ERROR_RATE_THRESHOLD', 2.0))  # %
WINDOW_SIZE = int(os.environ.get('WINDOW_SIZE', 200))
ALERT_COOLDOWN_SEC = int(os.environ.get('ALERT_COOLDOWN_SEC', 300))

# Track recent requests and pool state
request_window = deque(maxlen=WINDOW_SIZE)
last_alert_time = {}  # Separate cooldowns per alert type
last_seen_pool = None  # ✅ Track the previous pool dynamically

# Regex to parse Nginx log line
LOG_REGEX = re.compile(
    r'pool=(?P<pool>\w+)\s+release=(?P<release>[\w.-]+)\s+upstream_status=(?P<upstream_status>[\d,\s-]+)\s+upstream=(?P<upstream>[\d.:,\s]+)'
)

# ==========================
# Functions
# ==========================

def parse_log_line(line):
    """Parse a single Nginx log line and return a dict."""
    match = LOG_REGEX.search(line)
    if match:
        data = match.groupdict()
        # Parse upstream to detect failover
        upstreams = [u.strip() for u in data['upstream'].split(',')]
        data['upstream_list'] = upstreams
        data['failover_detected'] = len(upstreams) > 1
        return data
    return None

def send_slack_alert(message, alert_type='general'):
    """Send an alert message to Slack with per-type cooldown."""
    global last_alert_time
    now = time.time()
    if alert_type in last_alert_time:
        if now - last_alert_time[alert_type] < ALERT_COOLDOWN_SEC:
            return  # prevent spamming
    
    payload = {"text": message}
    try:
        response = requests.post(SLACK_WEBHOOK_URL, json=payload)
        if response.status_code == 200:
            print(f"✅ Slack alert sent ({alert_type}): {message}")
        else:
            print(f"❌ Failed to send Slack alert: {response.status_code}")
        last_alert_time[alert_type] = now
    except Exception as e:
        print(f"❌ Error sending Slack alert: {e}")

def check_error_rate():
    """Check the error rate in the current window."""
    if len(request_window) < 10:  # ✅ Wait for at least 10 requests
        return
    
    errors = sum(1 for status in request_window if '5' in str(status))
    rate = (errors / len(request_window)) * 100
    
    if rate >= ERROR_RATE_THRESHOLD:
        send_slack_alert(
            f"⚠️ *High Error Rate Alert*\n"
            f"Error Rate: {rate:.2f}%\n"
            f"Errors: {errors}/{len(request_window)} requests\n"
            f"Threshold: {ERROR_RATE_THRESHOLD}%",
            alert_type='error_rate'
        )

def check_failover(pool, upstream_list, failover_in_request):
    """Detect pool changes and failover events."""
    global last_seen_pool
    
    # Detect failover within a single request (multiple upstreams tried)
    if failover_in_request:
        send_slack_alert(
            f"🔄 *Failover Detected in Request*\n"
            f"Nginx tried multiple upstreams: {', '.join(upstream_list)}\n"
            f"Final pool: {pool}",
            alert_type='failover_request'
        )
    
    # Detect pool change between requests
    if last_seen_pool is not None and pool != last_seen_pool:
        send_slack_alert(
            f"🔄 *Pool Switch Detected*\n"
            f"Traffic shifted: {last_seen_pool} → {pool}\n"
            f"Primary pool may be down!",
            alert_type='pool_switch'
        )
    
    last_seen_pool = pool

def tail_log_file():
    """Tail the Nginx access log file and process new lines."""
    print(f"👀 Starting to watch: {LOG_FILE}")
    while not os.path.exists(LOG_FILE):
        print(f"⏳ Waiting for {LOG_FILE} to be created...")
        time.sleep(2)

    with open(LOG_FILE, 'r') as f:
        f.seek(0, 2)  # Go to end of file
        while True:
            try:
                line = f.readline()
                if not line:
                    time.sleep(0.5)
                    continue
                
                parsed = parse_log_line(line)
                if parsed:
                    pool = parsed['pool']
                    upstream_status = parsed['upstream_status']
                    
                    # Track request status
                    if upstream_status and upstream_status != '-':
                        # Get the final status (after comma if multiple)
                        final_status = upstream_status.split(',')[-1].strip()
                        request_window.append(final_status)
                    
                    # Check for failover and pool changes
                    check_failover(pool, parsed['upstream_list'], parsed['failover_detected'])
                    
                    # Check error rate
                    check_error_rate()
                    
            except Exception as e:
                print(f"❌ Error processing line: {e}")
                time.sleep(1)

# ==========================
# Main
# ==========================
if __name__ == "__main__":
    print("="*50)
    print("🔍 Blue/Green Deployment Monitor Starting")
    print("="*50)
    print(f"📊 Configuration:\n"
          f" - Error Rate Threshold: {ERROR_RATE_THRESHOLD}%\n"
          f" - Window Size: {WINDOW_SIZE} requests\n"
          f" - Alert Cooldown: {ALERT_COOLDOWN_SEC} seconds\n"
          f" - Log File: {LOG_FILE}\n"
          f" - Slack Webhook: {'Configured' if SLACK_WEBHOOK_URL else 'Not Configured'}\n")
    tail_log_file()