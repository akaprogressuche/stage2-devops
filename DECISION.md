# My Journey Building This Blue/Green Deployment System

This document is basically my notes on how I figured things out while building this project. I made a lot of mistakes along the way, so hopefully this helps if you're trying to understand my choices (or if I need to remember why I did something six months from now).

## Starting Point: Wait, What's Blue/Green?

Honestly, when I first saw this task, I had to Google "Blue/Green deployment" because I'd only vaguely heard the term before. After reading Martin Fowler's article and watching a few YouTube videos, it clicked: you run two identical versions of your app, switch traffic between them.

The tricky part was figuring out HOW to actually make that switch happen automatically.

## My First (Bad) Idea

My initial thought was: "I'll write a bash script that checks if Blue is healthy, and if not, update the Nginx config to point to Green!"

I even started writing it:
```bash
if ! curl http://blue:3000/health; then
  sed -i 's/blue/green/' nginx.conf
  nginx -s reload
fi
```

This felt wrong though. What if the script crashes? What if it runs while I'm deploying? This is fragile.

Then I found Nginx's `backup` directive and had one of those "oh duh" moments - Nginx ALREADY knows how to do this! I don't need to write my own health check logic.

## Why I Used Nginx's Built-In Failover

After reading the Nginx upstream docs (which took me two reads to understand), I discovered:

```nginx
upstream backend {
    server app_blue:3000 max_fails=2 fail_timeout=5s;
    server app_green:3000 backup;
}
```

That `backup` keyword means "only send traffic here if the primary is down." That's literally what Blue/Green deployment is!

**Why this is better than my bash script:**
- Nginx checks health automatically (I don't have to write a cron job)
- Happens on every request (my script would only check every 30 seconds)
- Battle-tested by millions of websites (my bash script... isn't)
- No moving parts (my script could crash, Nginx is always running)

I felt kinda dumb that I almost reinvented something that already exists, but hey, that's learning.

## The Timeout Rabbit Hole

This took me FOREVER to get right.

**First attempt:** 10 second timeouts
- Result: When Blue failed, users waited 10+ seconds for a response
- That's terrible UX

**Second attempt:** 1 second timeouts
- Result: Sometimes normal requests took 1.5 seconds and got failed over unnecessarily
- Blue/Green were constantly switching, it was chaos

**Final attempt:** 2 second timeouts
```nginx
proxy_connect_timeout 2s;
proxy_read_timeout 2s;
```

This seems to be the sweet spot. Fast enough that failures are caught quickly, slow enough that normal latency doesn't cause false alarms.

I figured this out by literally testing with different values and watching the logs. No shortcut here, just trial and error.

## Docker Compose vs Raw Docker Commands

I started by running containers manually to understand containers before using the docker hub images sent:

```bash
docker run -d --name app_blue -p 8081:3000 ...
docker run -d --name app_green -p 8082:3000 ...
docker run -d --name nginx ...
docker network create ...
docker network connect ...
```

This got old FAST. Every time I wanted to restart, I had to type all these commands again.

Then I learned about Docker Compose. Game changer:

```yaml
services:
  app_blue:
    # all the config here
```

Now it's just `docker-compose up`. So much cleaner.

**Why I wish I'd done this from day one:**
- Don't have to remember all the flags
- Easy to share with others (just one file)
- Can use environment variables easily
- Automatic network creation

I wasted probably 2 hours manually typing docker commands before switching to Compose. Learn from my mistake.

## The Headers Problem

So the apps were working, failover was working, but the `X-App-Pool` and `X-Release-Id` headers weren't showing up.

I spent an hour thinking my app code was broken. I'd curl Blue directly:
```bash
curl -I http://localhost:8081/version
X-App-Pool: blue  # ← There it is!
```

But through Nginx:
```bash
curl -I http://localhost:8080/version
# Where did it go??
```

Turns out Nginx has a default list of headers it forwards, and custom headers aren't on it. You have to explicitly tell Nginx to pass them through:

```nginx
proxy_pass_header X-App-Pool;
proxy_pass_header X-Release-Id;
```

I found this on StackOverflow and AI after searching "nginx not forwarding custom headers" for like 20 minutes. The answer said to use `proxy_pass_header` and explained that it's different from `add_header` (which would overwrite the app's headers).

This is the kind of thing that seems obvious in retrospect but wasn't intuitive at all when I was stuck.

## Health Checks Were Annoying

My first docker-compose.yml had health checks, and containers kept failing:

```
app_blue | wget: not found
```

I was confused - wget is like... a basic command, right? Nope! Not in Alpine Linux images. They're stripped down to be tiny.

**Two options:**
1. Don't use health checks (works but not ideal)
2. Install wget in the Dockerfile

I went with option 2:
```dockerfile
RUN apk add --no-cache wget curl
```

Also had to increase the `start_period` because Node.js apps take a few seconds to start:
```yaml
healthcheck:
  start_period: 20s  # Give it time to start up
```

Without this, the container would start, fail the health check immediately (because the app hadn't started yet), get marked unhealthy, and Nginx wouldn't route to it. Confusing!

## Why I Chose `max_fails=2` Instead of 1

At first I had `max_fails=1` because I thought "fail fast, right?"

Wrong. Here's what happened:

Sometimes a request would randomly time out (network hiccup, whatever). With `max_fails=1`, that single timeout would mark Blue as down and switch everything to Green. Then Blue would be fine again, switch back. Back and forth, constantly.

With `max_fails=2`, you need TWO consecutive failures. This filters out random hiccups but still catches real problems.

I figured this out by watching the logs during testing. With `max_fails=1`, I saw tons of unnecessary failovers. With `max_fails=2`, only real failures triggered switching.

## What I'd Do Differently

Looking back, here's what I'd change:

**1. Read the Nginx docs first**
I spent hours trying stuff that didn't work before finally reading the actual documentation. Would've saved time to start there.

**2. Use Docker Compose from the start**
Those first few hours with raw docker commands were wasted. Compose makes everything easier.

**3. Test one thing at a time**
I kept changing multiple things at once (timeouts + health checks + upstream config), so when something broke, I didn't know what caused it.

Better approach: change one thing, test, move on.

**4. Keep a testing checklist**
I kept forgetting to test certain scenarios. Should've written down:
- [ ] Normal state (Blue active)
- [ ] Chaos mode (Blue fails)
- [ ] Recovery (Blue comes back)
- [ ] Headers present
- [ ] No errors during failover

Would've caught issues earlier.

## Things I'm Still Not 100% Sure About

**Question 1:** Is 2 seconds the BEST timeout, or just "good enough"?

I tested 1s, 2s, 5s, 10s and 2s worked well. But maybe 2.5s or 3s would be better? I'm not sure. Would need to test with real production traffic patterns.

**Question 2:** Should I use `least_conn` or `round_robin` if I add multiple Blue/Green instances?

Right now it's just one of each, so the load balancing algorithm doesn't matter. But if I scaled to 2 Blues and 2 Greens, which algorithm is better? Don't know yet.

**Question 3:** Is `fail_timeout=5s` too short?

This means "try Blue again after 5 seconds." Maybe should be longer? Or shorter? I picked 5 because it "felt right" but that's not very scientific.

These are things I'd need to test in a real production environment to know for sure.

## What i Learnt

The biggest thing I learned: **simple is better than clever.**

I almost built this elaborate system with health check scripts, custom failover logic, monitoring daemons, etc. In the end, Nginx's built-in features + Docker Compose did everything I needed.

The whole solution is like 150 lines of config across 3 files. No custom code. Just configuration.

That's kinda beautiful, actually. Use the tools that exist instead of building new ones.

## How Long This Actually Took

**Day 1 (3 hours):** Reading about Blue/Green, understanding the task, trying stuff that didn't work

**Day 2 (2 hours):** Got basic Nginx + Docker Compose setup working

**Day 3 (2 hours):** Fighting with health checks and Alpine Linux

**Day 4 (1 hour):** Testing different timeout values, header forwarding

**Total:** ~8 hours of actual work, spread over 4 days

Most of the time wasn't coding - it was reading documentation, testing, breaking things, fixing them, and learning why things work the way they do.

## Resources That Actually Helped

**Documentation I read:**
- Nginx upstream module docs (http://nginx.org/en/docs/http/ngx_http_upstream_module.html)
- Docker Compose health checks (https://docs.docker.com/compose/compose-file/#healthcheck)
- Martin Fowler's Blue-Green article (https://martinfowler.com/bliki/BlueGreenDeployment.html)
- ChatGPT and ClaudeAI

**StackOverflow answers I found:**
- "Nginx not forwarding custom headers" (that's where I learned about proxy_pass_header)
- "Docker healthcheck wget not found" (learned about Alpine not having wget)
- Various answers about Nginx timeout tuning

**Videos I watched:**
- A YouTube video explaining Blue/Green vs Canary deployments (helped clarify the concept)
- Someone's tutorial on Docker Compose networking (understood how containers communicate)

## What I'm Proud Of

This isn't a perfect solution, but I'm happy with:

1. **It actually works** - Failover happens automatically, zero errors reach users
2. **It's simple** - Anyone can read the config and understand what's happening
3. **It's reliable** - Used battle-tested tools (Nginx, Docker), not custom code
4. **I learned a ton** - Now I actually understand how reverse proxies work

## Final Thoughts

Before this task, I kinda knew what Blue/Green deployment was in theory. Now I've actually built one and understand why each piece matters.

The failures taught me more than the successes. Every time something broke, I had to dig into the docs, understand WHY it broke, and fix it properly (not just band-aid it).

That's the thing about DevOps - you can read all the tutorials you want, but until you actually deploy something and watch it fail (and fix it), you don't really get it.

Now when I see "Nginx upstream" or "Docker health checks" in job descriptions, I'm not intimidated. I've wrestled with these things and won (eventually).

---

**P.S.** If you're reading this and trying to build your own Blue/Green setup, don't get discouraged when things don't work right away. I probably ran `docker-compose down && docker-compose up` about 50 times while building this. That's normal.

Just keep iterating, read the error messages, and Google stuff you don't understand. You'll get there.

**Time spent writing this document:** 45 minutes  
**Number of times I got distracted:** 3  
**Coffee consumed:** 2 cups ☕