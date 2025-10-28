# Blue/Green Deployment with Nginx Auto-Failover

My implementation of a Blue/Green deployment system for Stage 2 DevOps task.

## What This Does

I built an automated failover system where:
- Two identical Node.js apps run side-by-side (Blue and Green)
- Nginx sits in front and routes traffic to the active one (Blue by default)
- When Blue fails, Nginx automatically switches to Green
- Users never see errors - failover happens transparently

## Why I Built It This Way

After reading about Blue/Green deployments, I realized the key is having Nginx handle the switching logic rather than doing it manually. This way, when something breaks, the system recovers itself without human intervention.

## How to Run This

### Requirements
- Docker and Docker Compose installed
- Ports 8080, 8081, 8082 available
- That's it!
- when testing i updated my security group (inbound traffice) to open on these ports

### Quick Start

```bash
# Clone this repo
git clone https://github.com/akaprogressuche/stage2-devops
cd stage2-devops

# Copy environment file
cp .env.example .env

# Edit .env with your image URLs
nano .env

# Start everything
docker-compose up -d

# Check it's working locally
curl http://localhost:8080/version
```

You should see JSON with `"pool": "blue"`.

## Testing the Failover

This is the fun part - watching it automatically switch!

```bash
# Break Blue on purpose
curl -X POST 'http://localhost:8081/chaos/start?mode=error'

# Now check which pool is serving requests
curl http://localhost:8080/version | jq '.pool'
```

It should say `"green"` now. The switch happened automatically!

To reset:
```bash
curl -X POST 'http://localhost:8081/chaos/stop'
```

## Project Structure

```
stage2-devops/
├── docker-compose.yml      # Orchestrates the 3 containers
├── nginx.conf.template     # Nginx config with failover logic
├── .env                    # Environment variables
├── .env.example           # Template for .env
└── README.md              # You're reading it
```

I kept it simple - just the files needed to make it work.

## Configuration

The `.env` file controls everything:

```env
BLUE_IMAGE=yimikaade/wonderful:devops-stage-two
GREEN_IMAGE=yimikaade/wonderful:devops-stage-two
ACTIVE_POOL=blue
RELEASE_ID_BLUE=blue-v1.0.0
RELEASE_ID_GREEN=green-v1.0.0
```

Change these to match your setup.

## How the Failover Works

I spent time figuring out the right Nginx settings. Here's what makes it work:

**In nginx.conf.template:**
```nginx
upstream backend {
    server app_blue:3000 max_fails=2 fail_timeout=5s;
    server app_green:3000 backup;
}
```

The `backup` directive is key - Green only gets traffic when Blue is marked as down.

**Detecting failures fast:**
```nginx
proxy_connect_timeout 2s;
proxy_read_timeout 2s;
```

These tight timeouts mean we detect problems quickly (under 2 seconds).

**Retrying automatically:**
```nginx
proxy_next_upstream error timeout http_500 http_502 http_503 http_504;
proxy_next_upstream_tries 2;
```

When Blue fails, Nginx immediately retries on Green within the same request. The client never knows there was a problem.

## Challenges I Faced

### Challenge 1: Headers Getting Stripped

Initially, the `X-App-Pool` and `X-Release-Id` headers weren't making it to clients. I learned about `proxy_pass_header`:

```nginx
proxy_pass_header X-App-Pool;
proxy_pass_header X-Release-Id;
```

This tells Nginx to forward those specific headers unchanged.

### Challenge 2: Health Checks Taking Too Long

My first attempt had Blue/Green containers crashing on startup. Turns out `wget` wasn't installed in the Alpine image. I fixed it by adding to the Dockerfile:

```dockerfile
RUN apk add --no-cache wget curl
```

Also gave containers more time to start:
```yaml
start_period: 20s
```

### Challenge 3: Finding the Right Timeout Values

I experimented with different timeout values:
- Too short (1s): False positives, constant switching
- Too long (10s): Slow failover, users notice lag
- Just right (2s): Fast detection, stable operation

The 2-second sweet spot came from testing different chaos scenarios.

## Testing

I created a test script that verifies:
1. ✓ All services start correctly
2. ✓ Normal state routes to Blue
3. ✓ Headers are present
4. ✓ Chaos triggers failover to Green
5. ✓ Zero failed requests during failover
6. ✓ ≥95% requests go to Green after Blue fails

Run it with:
```bash
chmod +x test-failover.sh
./test-failover.sh
```

## What I Learned

Building this taught me:
- How Nginx upstream health checks work
- The difference between `backup` and round-robin load balancing
- Why idempotency matters (running the script multiple times should be safe)
- Docker Compose dependencies with health checks
- How to debug container networking issues

The biggest moment was realizing that Nginx can handle ALL the failover logic. I don't need external tools like HAProxy or complicated scripts - Nginx already has everything built in.

## Production Considerations

If I were deploying this for real, I'd add:
- Automated rollback if Green also fails

But for this task, the current setup demonstrates the core concept cleanly.

## Resources That Helped

- Nginx upstream documentation
- Martin Fowler's article on Blue-Green deployments
- Docker Compose health check docs
- StackOverflow (debugging the header forwarding issue)

## Troubleshooting

**Services won't start?**
```bash
docker-compose logs
```
Usually it's either port conflicts or missing environment variables.

**Failover not working?**
Check Nginx logs to see upstream switching:
```bash
docker-compose logs nginx | grep upstream
```

**Headers missing?**
Make sure `proxy_pass_header` directives are in nginx.conf.template.

Built for DevOps Stage 2 task, October 2025.