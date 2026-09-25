# tor-socat

DNS-over-TLS resolver through Tor using **socat** with multi-tier failover.

## What it does

Routes your DNS queries through the Tor network to encrypted upstream DNS resolvers. socat relays raw TCP streams through Tor's SOCKS4A proxy, providing transparent TLS passthrough — the TLS session is end-to-end between your client and the upstream resolver.

**Legacy listener, port 853 (Cloudflare only, in failover order):**
1. Cloudflare .onion hidden DNS resolver (most private)
2. Cloudflare 1.1.1.1 via a Tor exit

**Identity-bound routes (one provider each, never another):** 18531 Cloudflare .onion, 18532 Cloudflare 1.1.1.1 via a Tor exit, 18533 Quad9 9.9.9.9 via a Tor exit. Your client verifies the provider's TLS name for the route it uses.

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
| `BRIDGE1`..`BRIDGE16` | *(none; required)* | obfs4 bridge lines; at least one, three for Conflux |
| `BRIDGE_EVAL` | `off` | In-container bridge evaluation: `off`, `auto`, `moat` or `force` |
| `SOCAT_MAX_CHILDREN` | `256` | Connection cap of the legacy 853 listener |
| `ROUTE_MAX_CHILDREN` | `128` | Connection cap of each route listener |

## Custom bridges

```bash
docker run -d --name=tor-socat \
  -e BRIDGE1="obfs4 IP:PORT FINGERPRINT cert=... iat-mode=0" \
  -e BRIDGE2="obfs4 IP:PORT FINGERPRINT cert=... iat-mode=0" \
  --restart=always sureserver/tor-socat:latest
```


## Architecture

```
Client --[DNS-over-TLS]--> socat --[SOCKS4A]--> Tor ---> upstream DoT resolver
```

- **socat** does raw TCP relay with transparent TLS passthrough (end-to-end encryption)
- **SOCKS4A** routes connections through Tor with remote hostname resolution (.onion support)
- Active **health checks** every 30s on the legacy 853 listener, with failover from the onion to the Cloudflare exit (an answer is required; a dropped connection counts as a failure)
- Tor restarts in place on request, with an acknowledgement (see the README)
- Uses **obfs4 bridges** via lyrebird to circumvent Tor censorship

## Supported platforms

`linux/amd64` | `linux/arm/v7` | `linux/arm64` | `linux/riscv64`

## Source

[GitHub](https://github.com/sureserverman/tor-socat)

## License

MIT
