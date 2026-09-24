<h1 align="center">
  <a href="https://github.com/sureserverman/tor-socat">
    <!-- Please provide path to your logo here -->
    <img src="docs/images/logo.svg" alt="Logo" width="100" height="100">
  </a>
</h1>

<div align="center">
  tor-socat
  <br />
  <a href="https://github.com/sureserverman/tor-socat/issues/new?assignees=&labels=bug&template=01_BUG_REPORT.md&title=bug%3A+">Report a Bug</a>
  ·
  <a href="https://github.com/sureserverman/tor-socat/issues/new?assignees=&labels=enhancement&template=02_FEATURE_REQUEST.md&title=feat%3A+">Request a Feature</a>
  .
  <a href="https://github.com/sureserverman/tor-socat/issues/new?assignees=&labels=question&template=04_SUPPORT_QUESTION.md&title=support%3A+">Ask a Question</a>
</div>

<div align="center">
<br />

[![Project license](https://img.shields.io/github/license/sureserverman/tor-socat.svg?style=flat-square)](LICENSE)

[![Pull Requests welcome](https://img.shields.io/badge/PRs-welcome-ff69b4.svg?style=flat-square)](https://github.com/sureserverman/tor-socat/issues?q=is%3Aissue+is%3Aopen+label%3A%22help+wanted%22)
[![code with love by sureserverman](https://img.shields.io/badge/%3C%2F%3E%20with%20%E2%99%A5%20by-sureserverman-ff1414.svg?style=flat-square)](https://github.com/sureserverman)

</div>

<details open="open">
<summary>Table of Contents</summary>

- [About](#about)
- [Usage](#usage)
- [Roadmap](#roadmap)
- [Project assistance](#project-assistance)
- [Authors & contributors](#authors--contributors)
- [Security](#security)
- [License](#license)

</details>

---

## About

> This is simple image of **TOR** and **socat** combined together to create local DNS proxy through TOR to CloudFlare's hidden DNS resolver\ 
> https://dns4torpnlfs2ifuz2s2yf3fc7rdmsbhm6rw75euj35pac6ap25zgqad.onion/

## Usage


> To use it as upstream server for other docker containers your command may look like:\
> `docker run -d --name=tor-socat --restart=always sureserver/tor-socat:latest`
> 
> If you want to access it from your host, publish port 853 like this:\
> `docker run -d --name=tor-socat -p 853:853 --restart=always sureserver/tor-socat:latest`
> 
> This image uses obfs4 bridges to access tor network. There is a pair of them in this image. If you want to use another ones, just do it like this:\
> `docker run -d --name=tor-socat -e BRIDGE1="obfs4 217.182.78.247:52234 FF98116BB1530B18EDFBD0721FEF9874ADB1346A cert=tPXL+y4Wk+oFiqWdGtSAJ2BhcJBBcSD3gNn6dbgvmojNXy7DSeygNuHx4PYXvM9B+fTCPg iat-mode=0" -e BRIDGE2="obfs4 217.182.78.247:52234 FF98116BB1530B18EDFBD0721FEF9874ADB1346A cert=tPXL+y4Wk+oFiqWdGtSAJ2BhcJBBcSD3gNn6dbgvmojNXy7DSeygNuHx4PYXvM9B+fTCPg iat-mode=0" --restart=always sureserver/tor-socat:latest`
> with your desired bridges' strings in quotes
> 
> After that just use IP-address of your container and port 853 as DNS-over-TLS upstream resolver

### Podman

> All the same commands work with Podman by replacing `docker` with `podman`:\
> `podman run -d --name=tor-socat --restart=always sureserver/tor-socat:latest`
>
> With host port published:\
> `podman run -d --name=tor-socat -p 853:853 --restart=always sureserver/tor-socat:latest`
>
> With custom bridges:\
> `podman run -d --name=tor-socat -e BRIDGE1="obfs4 IP:PORT FINGERPRINT cert=... iat-mode=0" -e BRIDGE2="obfs4 IP:PORT FINGERPRINT cert=... iat-mode=0" --restart=always sureserver/tor-socat:latest`
>
> To generate a systemd service for auto-start:\
> `podman generate systemd --name tor-socat --new > ~/.config/systemd/user/tor-socat.service`\
> `systemctl --user enable --now tor-socat.service`


## Routes

> Port 853 is the legacy listener: the Cloudflare .onion first, Cloudflare's 1.1.1.1 via a Tor exit as backup. It is Cloudflare only. The earlier Quad9 (9.9.9.9) fallback was removed, because a client that authenticates a Cloudflare name must never have its stream handed to another provider.
>
> Three identity-bound routes reach exactly one provider each, with no backup or fallback to another provider:
>
> | Port | Route | Destination (through Tor, SOCKS4A) |
> |---|---|---|
> | 18531 | cloudflare-onion | Cloudflare's resolver .onion |
> | 18532 | cloudflare-exit | 1.1.1.1:853 via a Tor exit |
> | 18533 | quad9-exit | 9.9.9.9:853 via a Tor exit |
>
> tor-haproxy offers the same routes but balances each exit route over two addresses of the same provider (adding 1.0.0.1 and 149.112.112.112); here each exit route has one address. Either way a route reaches exactly one provider.
>
> The TLS session is end to end between your client and the provider. Your client must verify the provider's name for the route it uses. The client, not this image, chooses between routes. Each route listener accepts at most `ROUTE_MAX_CHILDREN` connections (default 128); 853 accepts `SOCAT_MAX_CHILDREN` (default 256). A stream idle for 180 seconds is closed, which outlasts a slow Tor round trip and a DNS client's kept-alive session.

## Restarting Tor without restarting the container

> As the image's own user (the default for `docker exec`/`podman exec`), write a request id (1–64 characters from `A-Za-z0-9._:-`; `legacy` is reserved) to `/app/data/control/tor-restart-request`. Write a temp file in the same directory and `mv` it, so the write is atomic. `/app/data/control` is 0700, so no other user can request a restart or forge an answer. Within about 5 seconds only Tor is restarted; the socat listeners keep running. The answer appears in `/app/data/control/tor-restart-ack` as tab-separated lines: `request_id`, `status` (`respawned` or `refused`), `generation`, `tor_pid` and `utc`. An invalid id is answered in `tor-restart-rejected` instead, never over a pending acknowledgement. `/app/data/control/tor-generation` always names the current generation and Tor pid. An acknowledgement means Tor was respawned, not that it has bootstrapped. Check readiness separately. Touching `/tmp/tor-restart-flag` is acknowledged as request id `legacy`. If `/tmp/bridges-current.env` exists at the restart, its bridges are used. This is the same contract as tor-haproxy.

## Roadmap

See the [open issues](https://github.com/sureserverman/tor-socat/issues) for a list of proposed features (and known issues).

- [Top Feature Requests](https://github.com/sureserverman/tor-socat/issues?q=label%3Aenhancement+is%3Aopen+sort%3Areactions-%2B1-desc) (Add your votes using the 👍 reaction)
- [Top Bugs](https://github.com/sureserverman/tor-socat/issues?q=is%3Aissue+is%3Aopen+label%3Abug+sort%3Areactions-%2B1-desc) (Add your votes using the 👍 reaction)
- [Newest Bugs](https://github.com/sureserverman/tor-socat/issues?q=is%3Aopen+is%3Aissue+label%3Abug)

## Project assistance

If you want to say **thank you** or/and support active development of tor-socat:

- Add a [GitHub Star](https://github.com/sureserverman/tor-socat) to the project.
- Tweet about the tor-socat.
- Write interesting articles about the project on [Dev.to](https://dev.to/), [Medium](https://medium.com/) or your personal blog.

Together, we can make tor-socat **better**!

## Authors & contributors

The original setup of this repository is by [Serverman](https://github.com/sureserverman).

For a full list of all authors and contributors, see [the contributors page](https://github.com/sureserverman/tor-socat/contributors).

## Security

tor-socat follows good practices of security, but 100% security cannot be assured.
tor-socat is provided **"as is"** without any **warranty**. Use at your own risk.

## License

This project is licensed under the **MIT license**.

See [LICENSE](LICENSE.md) for more information.
