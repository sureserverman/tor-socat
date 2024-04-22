<h1 align="center">
  <a href="https://github.com/sureserverman/tor-socat">
    <!-- Please provide path to your logo here -->
    <img src="docs/images/logo.svg" alt="Logo" width="100" height="100">
  </a>
</h1>

<div align="center">
  Bootstrap scripts for easy server setup
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
  - [Built With](#built-with)
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Installation](#installation)
- [Usage](#usage)
- [Roadmap](#roadmap)
- [Project assistance](#project-assistance)
- [Authors & contributors](#authors--contributors)
- [Security](#security)
- [License](#license)

</details>

---

## About

> **[?]**
> This is simple image of **TOR** and **socat** combined together to create local DNS proxy through TOR to CloudFlare's hidden DNS resolver\ 
> https://dns4torpnlfs2ifuz2s2yf3fc7rdmsbhm6rw75euj35pac6ap25zgqad.onion/
> 
> To use it as upstream server for other docker containers your command may look like:\
> `docker run -d --name=socat-tor --restart=always sureserver/tor-socat`
> 
> If you want to access it from your host, publish port 853 like this:\
> `docker run -d --name=socat-tor -p 853:853 --restart=always sureserver/tor-socat`
> 
> This image uses obfs4 bridges to access tor network. There is a pair of them in this image. If you want to use another ones, just do it like this:\
> `docker run -d --name=socat-tor -e bridge1="obfs4 217.182.78.247:52234 FF98116BB1530B18EDFBD0721FEF9874ADB1346A cert=tPXL+y4Wk+oFiqWdGtSAJ2BhcJBBcSD3gNn6dbgvmojNXy7DSeygNuHx4PYXvM9B+fTCPg iat-mode=0" -e bridge2="obfs4 217.182.78.247:52234 FF98116BB1530B18EDFBD0721FEF9874ADB1346A cert=tPXL+y4Wk+oFiqWdGtSAJ2BhcJBBcSD3gNn6dbgvmojNXy7DSeygNuHx4PYXvM9B+fTCPg iat-mode=0" --restart=always sureserver/tor-socat`
> with your desired bridges' strings in quotes
> 
> After that just use IP-address of your container and port 853 as DNS-over-TLS upstream resolver


### Built With

> **[?]**
> Pure bash and bash only. No strings attached.

## Getting Started

### Prerequisites

> **[?]**
> This scripts set is intended for usage only with ubuntu 22.04 servers. It wasn't tested on any other operating system and I doubt it could work on them, because all the commands and repositories in this script were used and tested only on this operating system 

### Installation

> **[?]**
> Describe how to install and get started with the project.

## Usage

> **[?]**
> This script usage: init.sh -[cmsxfuhprabH]
> Flags determine everything
> Install: Matrix -m, Caddy -c, Xray -x, SSH honeypot -H
> Set up: SSH -s, UFW -u, Fail2ban -f
> SSH options: Custom port -p, Disable root login -r, Disable banners verbosity -b, Disable unsafe authentication methods -a
> -h or no flags Print this help

## Roadmap

See the [open issues](https://github.com/sureserverman/tor-socat/issues) for a list of proposed features (and known issues).

- [Top Feature Requests](https://github.com/sureserverman/tor-socat/issues?q=label%3Aenhancement+is%3Aopen+sort%3Areactions-%2B1-desc) (Add your votes using the 👍 reaction)
- [Top Bugs](https://github.com/sureserverman/tor-socat/issues?q=is%3Aissue+is%3Aopen+label%3Abug+sort%3Areactions-%2B1-desc) (Add your votes using the 👍 reaction)
- [Newest Bugs](https://github.com/sureserverman/tor-socat/issues?q=is%3Aopen+is%3Aissue+label%3Abug)

## Project assistance

If you want to say **thank you** or/and support active development of Bootstrap scripts for easy server setup:

- Add a [GitHub Star](https://github.com/sureserverman/tor-socat) to the project.
- Tweet about the Bootstrap scripts for easy server setup.
- Write interesting articles about the project on [Dev.to](https://dev.to/), [Medium](https://medium.com/) or your personal blog.

Together, we can make Bootstrap scripts for easy server setup **better**!

## Authors & contributors

The original setup of this repository is by [Serverman](https://github.com/sureserverman).

For a full list of all authors and contributors, see [the contributors page](https://github.com/sureserverman/tor-socat/contributors).

## Security

Bootstrap scripts for easy server setup follows good practices of security, but 100% security cannot be assured.
Bootstrap scripts for easy server setup is provided **"as is"** without any **warranty**. Use at your own risk.

_For more information and to report security issues, please refer to our [security documentation](docs/SECURITY.md)._

## License

This project is licensed under the **GPLv3 license**.

See [LICENSE](LICENSE.md) for more information.
