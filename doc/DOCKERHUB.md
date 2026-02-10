# tor-socat

DNS-over-TLS resolver through Tor using **socat** with multi-tier failover.

## What it does

Routes your DNS queries through the Tor network to encrypted upstream DNS resolvers. socat relays raw TCP streams through Tor's SOCKS4A proxy, providing transparent TLS passthrough — the TLS session is end-to-end between your client and the upstream resolver.

**Upstream resolvers (in failover order):**
1. Cloudflare .onion hidden DNS resolver (most private)
2. Cloudflare 1.1.1.1
3. Quad9 9.9.9.9

Clients connect via **DNS-over-TLS** — socat passes TLS through transparently.

## Quick start

```bash
docker run -d --name=tor-socat -p 853:853 --restart=always sureserver/tor-socat:latest
```

Then point your DNS client to `127.0.0.1:853` as a DNS-over-TLS upstream.

## As upstream for other containers

```bash
docker run -d --name=tor-socat --restart=always sureserver/tor-socat:latest
```

Use the container IP and port 853 as a DNS-over-TLS upstream in your resolver (Unbound, Pi-hole, etc.).

## Podman

```bash
podman run -d --name=tor-socat -p 853:853 --restart=always sureserver/tor-socat:latest
```

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `853` | Listening port (853 for DoT, 443 for DoH, 53 for DNS) |
| `BRIDGE1` | *(built-in)* | First obfs4 bridge string |
| `BRIDGE2` | *(built-in)* | Second obfs4 bridge string |
| `BRIDGED` | *(enabled)* | Set to `N` to disable obfs4 bridges |

## Custom bridges

```bash
docker run -d --name=tor-socat \
  -e BRIDGE1="obfs4 IP:PORT FINGERPRINT cert=... iat-mode=0" \
  -e BRIDGE2="obfs4 IP:PORT FINGERPRINT cert=... iat-mode=0" \
  --restart=always sureserver/tor-socat:latest
```

## Different protocols

```bash
# DNS-over-HTTPS
docker run -d --name=tor-socat -e PORT=443 --restart=always sureserver/tor-socat:latest

# Plain DNS
docker run -d --name=tor-socat -e PORT=53 --restart=always sureserver/tor-socat:latest
```

## Architecture

```
Client --[DNS-over-TLS]--> socat --[SOCKS4A]--> Tor ---> upstream DoT resolver
```

- **socat** does raw TCP relay with transparent TLS passthrough (end-to-end encryption)
- **SOCKS4A** routes connections through Tor with remote hostname resolution (.onion support)
- Shell-based **monitor_and_failover** detects connection errors and switches to backup upstreams
- Uses **obfs4 bridges** via lyrebird to circumvent Tor censorship

## Supported platforms

`linux/amd64` | `linux/arm/v7` | `linux/arm64` | `linux/riscv64`

## Source

[GitHub](https://github.com/sureserverman/tor-socat)

## License

GPLv3
