# CLAUDE.md - AI Assistant Guide for tor-socat

## Project Overview

**tor-socat** is a Docker-based privacy tool that combines Tor and socat to create a local DNS proxy through the Tor network to CloudFlare's hidden DNS resolver. This enables secure, anonymous DNS resolution using DNS-over-TLS (DoT), DNS-over-HTTPS (DoH), or plain DNS.

### Key Technologies
- **Tor**: Anonymous network routing with obfs4 bridge support
- **socat**: Network traffic forwarding utility
- **lyrebird**: obfs4 pluggable transport implementation
- **Alpine Linux**: Lightweight container base image
- **Docker**: Containerization platform

### Primary Use Cases
1. DNS-over-TLS (default port 853) through Tor
2. DNS-over-HTTPS (configurable port 443)
3. Plain DNS (configurable port 53)
4. Privacy-focused DNS resolution bypassing censorship

---

## Codebase Structure

```
tor-socat/
├── .github/
│   └── workflows/
│       └── main.yml          # Multi-arch Docker build CI/CD pipeline
├── Dockerfile                # Container image definition
├── start.sh                  # Entrypoint script with failover logic
├── torrc                     # Tor configuration file
├── README.md                 # User-facing documentation
├── LICENSE.md                # GPLv3 license
└── .gitignore               # Git ignore rules
```

### File Descriptions

#### `Dockerfile` (17 lines)
Defines the Alpine Linux-based container image with:
- Package installations: tor, socat, bind-tools, tini, lyrebird
- Environment variables for configuration
- Health check using `dig` to verify DNS functionality
- Tini as init system for proper signal handling

#### `start.sh` (29 lines)
Main entrypoint script featuring:
- **Lines 2-6**: Conditional Tor startup with bridge support
- **Lines 8-24**: `monitor_and_failover()` function that monitors primary connection and fails over to backup
- **Lines 27-29**: Primary connection to onion address, backup to clearnet 1.1.1.1
- Real-time output monitoring with failure pattern detection

#### `torrc` (2 lines)
Minimal Tor configuration:
- Configures obfs4 pluggable transport using lyrebird

#### `.github/workflows/main.yml` (107 lines)
Multi-architecture CI/CD pipeline:
- Triggers on version tags (v*)
- Builds for: linux/amd64, linux/arm/v7, linux/arm64
- Publishes to Docker Hub: `sureserver/tor-socat`
- Uses digest-based manifest creation for multi-arch support

---

## Architecture & Data Flow

### Component Interaction

```
User Request → socat (port 853/443/53) → Tor (SOCKS4A:9050) → [Tor Network] → CloudFlare Hidden Service
                                                                    ↓
                                                            Fallback to 1.1.1.1
```

### Failover Mechanism
1. **Primary**: Connect to CloudFlare onion service
   - `dns4torpnlfs2ifuz2s2yf3fc7rdmsbhm6rw75euj35pac6ap25zgqad.onion`
2. **Backup**: On failure, fallback to CloudFlare clearnet
   - `1.1.1.1` (still routed through Tor)
3. **Detection**: Monitors for error patterns in real-time output
   - Patterns: "rejected", "failed", "refused", "unreachable", "timeout"

### Recent Improvements (from commit history)
- **b0f23f6**: Enhanced healthcheck reliability
- **da0fe51**: Improved failover mechanism
- **493c02f**: Fixed onion service failure handling
- **53c996d**: Disabled bridges by default (BRIDGED="N")

---

## Environment Variables

### Configuration Options

| Variable | Default | Description | Example |
|----------|---------|-------------|---------|
| `PORT` | `853` | Service port (853=DoT, 443=DoH, 53=DNS) | `PORT=443` |
| `BRIDGED` | `"N"` | Enable obfs4 bridge mode | `BRIDGED="Y"` |
| `BRIDGE1` | `''` | First obfs4 bridge configuration | See below |
| `BRIDGE2` | `''` | Second obfs4 bridge configuration | See below |

### Bridge Configuration Example
```bash
BRIDGE1="obfs4 217.182.78.247:52234 FF98116BB1530B18EDFBD0721FEF9874ADB1346A cert=tPXL+y4Wk+oFiqWdGtSAJ2BhcJBBcSD3gNn6dbgvmojNXy7DSeygNuHx4PYXvM9B+fTCPg iat-mode=0"
```

---

## Development Workflow

### Local Testing

#### 1. Build the Image
```bash
docker build -t tor-socat:dev .
```

#### 2. Run with Default Configuration (DoT)
```bash
docker run -d --name=tor-socat-test -p 853:853 tor-socat:dev
```

#### 3. Run with Custom Configuration
```bash
# DNS-over-HTTPS
docker run -d --name=tor-socat-https -e PORT=443 -p 443:443 tor-socat:dev

# With obfs4 bridges
docker run -d --name=tor-socat-bridged \
  -e BRIDGED="Y" \
  -e BRIDGE1="<bridge-config-1>" \
  -e BRIDGE2="<bridge-config-2>" \
  tor-socat:dev
```

#### 4. Monitor Logs
```bash
docker logs -f tor-socat-test
```

#### 5. Test DNS Resolution
```bash
# Using dig
dig +short +tls -p 853 @localhost google.com

# Using kdig (better TLS support)
kdig +tls -p 853 @localhost google.com
```

### Debugging

#### Check Container Health
```bash
docker inspect --format='{{.State.Health.Status}}' tor-socat-test
```

#### Interactive Shell Access
```bash
docker exec -it tor-socat-test /bin/sh
```

#### Check Tor Status
```bash
docker exec tor-socat-test ps aux | grep tor
```

#### View socat Connections
```bash
docker exec tor-socat-test netstat -tlnp | grep ${PORT}
```

---

## Docker Build & Deployment

### CI/CD Pipeline (GitHub Actions)

#### Trigger
- Automatically runs on git tags matching `v*` pattern
- Example: `git tag v1.0.0 && git push origin v1.0.0`

#### Build Process
1. **Matrix Build**: Parallel builds for 3 architectures
   - linux/amd64 (x86_64)
   - linux/arm/v7 (32-bit ARM)
   - linux/arm64 (64-bit ARM)
2. **Digest Export**: Each build exports its digest
3. **Manifest Merge**: Creates unified multi-arch manifest
4. **Push**: Publishes to `sureserver/tor-socat` on Docker Hub

#### Required Secrets
- `DOCKERHUB_USERNAME`: Docker Hub username
- `DOCKERHUB_TOKEN`: Docker Hub access token

### Manual Release Process
```bash
# 1. Ensure all changes are committed
git add -A
git commit -m "Release preparation"

# 2. Create version tag
git tag -a v1.0.0 -m "Release v1.0.0: Description of changes"

# 3. Push tag to trigger CI/CD
git push origin v1.0.0

# 4. Monitor GitHub Actions
# Visit: https://github.com/sureserverman/tor-socat/actions
```

---

## Key Conventions & Best Practices

### Shell Scripting (start.sh)
1. **POSIX Compliance**: Use `#!/bin/sh` not `#!/bin/bash`
2. **Variable Quoting**: Always quote variables: `"$VARIABLE"`
3. **Error Handling**: Check exit codes and fail appropriately
4. **Background Processes**: Use `&` for Tor daemon, foreground for socat
5. **Signal Handling**: Tini ensures proper signal propagation

### Dockerfile Best Practices
1. **Minimal Base**: Alpine Linux for small image size
2. **No Cache**: Use `apk --no-cache` to minimize layers
3. **Explicit Versions**: Consider pinning package versions for reproducibility
4. **Single RUN**: Combine related commands to reduce layers
5. **Health Checks**: Always include meaningful health checks

### Version Control
1. **Commit Messages**: Follow conventional commits format
   - Examples: "fix: onion fail", "feat: improved healthcheck"
2. **Branching**: Development on feature branches, merge to main
3. **Tagging**: Semantic versioning (v1.2.3) for releases

### Code Comments
- Use comments sparingly, prefer self-documenting code
- Document complex logic (like failover mechanism)
- Explain non-obvious configurations

---

## Testing Guidelines

### Functional Tests

#### 1. DNS Resolution Test
```bash
# Should return IP address
dig +short +tls -p 853 @localhost google.com
```

#### 2. Tor Connectivity Test
```bash
# Check Tor circuit status
docker exec tor-socat-test cat /var/lib/tor/state | grep CircuitBuildTimeout
```

#### 3. Failover Test
```bash
# Monitor logs during onion service issues
docker logs -f tor-socat-test | grep -E "(PRIMARY|backup)"
```

#### 4. Health Check Test
```bash
# Should show "healthy" after ~30 seconds
docker inspect tor-socat-test | jq '.[0].State.Health'
```

### Performance Tests

#### 1. DNS Response Time
```bash
# Measure query time
time dig +tls -p 853 @localhost google.com
```

#### 2. Concurrent Requests
```bash
# Test with multiple parallel queries
for i in {1..10}; do
  dig +short +tls -p 853 @localhost example${i}.com &
done
wait
```

### Security Tests

#### 1. Verify Tor Circuit
```bash
# DNS leak test (should show Tor exit IP, not your real IP)
dig +short +tls -p 853 @localhost whoami.akamai.net
```

#### 2. Port Exposure Check
```bash
# Only configured PORT should be open
docker port tor-socat-test
```

---

## Common AI Assistant Tasks

### 1. Updating Dependencies
```bash
# Check for Alpine package updates
docker run --rm alpine:latest apk update && apk list --upgradable
```

When updating packages in Dockerfile:
- Test thoroughly before committing
- Update health check if DNS resolution changes
- Check compatibility with ARM architectures

### 2. Modifying Failover Logic
Location: `start.sh` lines 9-24

Key considerations:
- Maintain backward compatibility
- Test both success and failure paths
- Ensure proper cleanup of failed connections
- Update error pattern regex carefully

### 3. Adding New Environment Variables
Steps:
1. Add ENV declaration in Dockerfile
2. Use variable in start.sh
3. Document in README.md
4. Update this CLAUDE.md file
5. Test with and without the variable set

### 4. Debugging Connection Issues
Checklist:
- [ ] Check Tor daemon is running: `ps aux | grep tor`
- [ ] Verify socat is listening: `netstat -tlnp`
- [ ] Check Tor logs: Look for circuit build failures
- [ ] Test without Tor: Direct connection to 1.1.1.1
- [ ] Check bridge configuration if BRIDGED="Y"
- [ ] Verify network connectivity from container

### 5. Performance Optimization
Areas to consider:
- socat timeout settings (currently -T3)
- Tor circuit build parameters
- Health check frequency
- Connection pooling (not currently implemented)

### 6. Security Enhancements
Potential improvements:
- DNSSEC validation (add `dnssec-trigger`)
- Request rate limiting
- Connection encryption verification
- Automated bridge rotation
- Monitor Tor consensus for bad exits

---

## Troubleshooting Guide

### Issue: Container Fails Health Check
**Symptoms**: Container marked as unhealthy after 30s
**Checks**:
1. `docker logs tor-socat-test` - check for errors
2. Verify Tor connected: Look for "Bootstrapped 100%"
3. Test manually: `docker exec tor-socat-test dig +short +tls @127.0.0.1 google.com`
4. Check port conflicts: `netstat -tlnp | grep ${PORT}`

### Issue: DNS Queries Timeout
**Symptoms**: Slow or failing DNS resolution
**Checks**:
1. Tor circuit issues: Check logs for circuit failures
2. Onion service unreachable: Should auto-failover to 1.1.1.1
3. Network connectivity: `docker exec tor-socat-test ping -c 3 1.1.1.1`
4. socat timeout too aggressive: Consider increasing -T3 to -T5

### Issue: Bridge Connections Fail
**Symptoms**: BRIDGED="Y" but no connection
**Checks**:
1. Verify bridge strings are complete and correctly formatted
2. Check lyrebird is running: `ps aux | grep lyrebird`
3. Test bridges individually
4. Try alternative bridges from https://bridges.torproject.org/

### Issue: Failover Not Triggering
**Symptoms**: Stays on failing primary connection
**Checks**:
1. Review error pattern regex in start.sh:18
2. Check if error messages match patterns
3. Verify pkill can terminate socat process
4. Test exec command for backup connection

---

## Architecture Decisions & Rationale

### Why Alpine Linux?
- Minimal attack surface
- Small image size (~50MB vs 200MB+ for Ubuntu)
- Fast container startup
- Sufficient package availability

### Why socat Instead of nginx/haproxy?
- Lightweight (single binary)
- Simple configuration (command-line only)
- Perfect for port forwarding use case
- No overhead of HTTP server features

### Why Tini as Init?
- Proper zombie process reaping
- Signal forwarding to child processes
- Graceful shutdown handling
- Minimal overhead (<100KB)

### Why Monitor-Based Failover?
- Real-time error detection
- No hard-coded timeout waiting
- Faster recovery than periodic health checks
- Captures all error scenarios

### Why SOCKS4A Instead of SOCKS5?
- Tor supports both, SOCKS4A is simpler
- Domain name resolution through SOCKS
- Sufficient for DNS forwarding needs

---

## Future Enhancement Opportunities

### High Priority
1. **IPv6 Support**: Add dual-stack DNS resolution
2. **Metrics Export**: Prometheus endpoint for monitoring
3. **Configurable Failover**: User-defined backup servers
4. **DNSSEC Validation**: Enhanced security

### Medium Priority
1. **Multiple Tor Circuits**: Load balancing across circuits
2. **Geographic Exit Selection**: Control exit node country
3. **Query Logging**: Optional privacy-preserving logs
4. **Custom Torrc**: User-provided Tor configuration

### Low Priority
1. **Web Dashboard**: Status and configuration UI
2. **Automatic Bridge Updates**: Fetch fresh bridges periodically
3. **Connection Pooling**: Reuse Tor circuits efficiently
4. **Split Tunneling**: Different circuits for different domains

---

## License & Attribution

**License**: GNU General Public License v3.0 (GPLv3)
- See LICENSE.md for full text
- Copyleft: Modifications must be open source
- Commercial use allowed with source disclosure

**Original Author**: [sureserverman](https://github.com/sureserverman)
**Repository**: https://github.com/sureserverman/tor-socat

---

## Quick Reference

### Essential Commands
```bash
# Build
docker build -t tor-socat .

# Run (basic)
docker run -d --name=tor-socat -p 853:853 sureserver/tor-socat

# Test
dig +short +tls -p 853 @localhost google.com

# Logs
docker logs -f tor-socat

# Health
docker inspect --format='{{.State.Health.Status}}' tor-socat

# Stop
docker stop tor-socat && docker rm tor-socat
```

### Important URLs
- **Docker Hub**: https://hub.docker.com/r/sureserver/tor-socat
- **GitHub**: https://github.com/sureserverman/tor-socat
- **Tor Bridges**: https://bridges.torproject.org/
- **CloudFlare Onion**: `dns4torpnlfs2ifuz2s2yf3fc7rdmsbhm6rw75euj35pac6ap25zgqad.onion`

### File Locations in Container
- Tor config: `/etc/tor/torrc`
- Tor data: `/var/lib/tor/`
- Startup script: `/bin/start.sh`
- Logs: stdout/stderr (via Docker)

---

## For AI Assistants: Development Best Practices

### Before Making Changes
1. Read and understand the entire file you're modifying
2. Check recent commits for context
3. Consider impact on all platforms (amd64, arm/v7, arm64)
4. Test locally before committing

### When Writing Code
1. Maintain POSIX shell compatibility (no bashisms)
2. Preserve existing error handling patterns
3. Add health checks for new functionality
4. Document environment variables
5. Update this CLAUDE.md file

### When Committing
1. Use descriptive commit messages
2. Reference issues if applicable
3. Update version tags for releases
4. Run local tests before pushing

### When Helping Users
1. Ask about their specific use case (DoT/DoH/DNS)
2. Check if they need bridge mode
3. Verify their Docker environment
4. Provide complete docker run commands
5. Include testing steps in responses

---

**Last Updated**: 2025-11-21 (Based on commit b0f23f6)
**Maintained By**: AI assistants should update this file when making significant changes
