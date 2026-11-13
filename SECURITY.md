# Security policy

Peep opens files from anywhere, so it treats every document as untrusted: rendered pages run
under a strict content security policy, load no remote content by default, and sanitize raw
HTML. [docs/VISION.md](docs/VISION.md) describes the security model.

## Supported versions

Security fixes go into the latest release. Please check that the problem still happens there
before reporting.

## Reporting a vulnerability

Please report vulnerabilities privately, not in a public issue, pull request, or discussion.

Use GitHub's private vulnerability reporting:
[Report a vulnerability](https://github.com/itspriddle/peep/security/advisories/new) (also under
the repository's **Security** tab > **Advisories**).

Include what you can of:

- the Peep version (`peep --version`, or About Peep) and macOS version
- what an attacker can do, and what they need (a crafted Markdown file, a theme, a link)
- steps or a file that reproduces it

The report stays private between you and the maintainers while it's investigated and fixed.
Once a fix ships, the advisory is published with credit to you, unless you'd rather not be
named.
