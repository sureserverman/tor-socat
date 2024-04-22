<h1 align="center">
  <a href="https://github.com/sureserverman/tor-socat">
    <!-- Please provide path to your logo here -->
    <img src="docs/images/logo.svg" alt="Logo" width="100" height="100">
  </a>
</h1>

<div align="center">
  tor-socat
  <br />
  <a href="#about"><strong>Explore the screenshots »</strong></a>
  <br />
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
>
> To use it for DNS-over-HTTPS do it this way:\
> `docker run -d --name=tor-socat --e PORT=443 --restart=always sureserver/tor-socat:latest`
> 
> To use it for DNS do it this way:\
> `docker run -d --name=tor-socat --e PORT=53 --restart=always sureserver/tor-socat:latest`
>
> To disable obfs4-bridges:\
> `docker run -d --name=tor-socat --e BRIDGED="N" --restart=always sureserver/tor-socat:latest`


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

This project is licensed under the **GPLv3 license**.

See [LICENSE](LICENSE.md) for more information.
