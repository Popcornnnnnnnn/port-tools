<div align="center">
  <img src="design/marketing/port-tools-icon-rounded.png" width="104" alt="Port Tools icon">
  <h1>Port Tools</h1>
  <p><strong>Turn localhost ports into projects, apps, and service types.</strong></p>
  <p>A local-first macOS menu-bar control plane for the development services already running on your Mac.</p>
  <p><strong>English</strong> · <a href="README.zh-CN.md">简体中文</a></p>
  <p>macOS 14+ · Native SwiftUI · Self-contained Go core · Local only</p>
</div>

<p align="center">
  <img src="design/marketing/github-hero.png" width="100%" alt="Port Tools in light and dark appearance with six local Web apps">
</p>

## `lsof` finds a PID. Port Tools finds the project behind it.

After a day of coding, `localhost:4178`, `localhost:4317`, and `localhost:7680` may all respond—but a port number does not tell you which repository, worktree, or application you are looking at.

Port Tools scans the listeners already running on your Mac and reconstructs their development context:

- repository, branch, and Git worktree;
- nearest application manifest and relative path;
- verified Web page versus supporting service;
- the local address you can actually open;
- whether the process can be stopped without guessing.

It turns a machine-level port table into a project-level map of your local development environment.

## Pain and solution, in the same place

| When this happens | Port Tools does this |
| --- | --- |
| “What project owns port `4178`?” | Follows process ancestry and working directories back to the repository, branch, worktree, and application. |
| “Why are there four `node` processes for one repo?” | Groups applications by project and separates visible Web pages from supporting services. |
| “The port changed again.” | Assigns a stable address such as `phone-studio.localhost:17890`. |
| “Can I safely kill this old server?” | Shows a reviewed stop plan, revalidates process identity, sends `SIGTERM`, and confirms that the listeners were released. |

## How it compares

Port Tools does not replace the tools developers already trust. It connects the context between them.

| Tool | Best at | What Port Tools adds |
| --- | --- | --- |
| [`lsof`](https://github.com/lsof-org/lsof) / `netstat` | Sockets, ports, and PIDs | Repository, worktree, application, Web classification, and a usable address |
| Activity Monitor | Process and resource inspection | A Web-service-first view organized around development projects |
| `kill-port` / [`fkill`](https://github.com/sindresorhus/fkill) | Freeing a port quickly | Ownership evidence, refusal rules, identity revalidation, and listener-release verification |
| [Portless](https://github.com/vercel-labs/portless) | Starting apps on stable named URLs | Discovery and classification of services that are already running |
| [Caddy](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy) | Flexible reverse-proxy infrastructure | Automatic local inventory and project-aware route ownership |
| Docker Desktop | Container and published-port management | One view for host processes, worktrees, applications, and conservative Docker handling |

## One local workflow

1. **Discover** HTTP/HTTPS listeners without changing how your app was started.
2. **Identify** the process, repository, worktree, application, and service role.
3. **Name** the service with a persistent `*.localhost` address.
4. **Open or copy** the address directly from the menu bar.
5. **Stop safely** only after reviewing and revalidating the target.

## How it works

The native SwiftUI menu-bar app talks to a bundled Go core over a private, owner-only Unix socket. The Go core discovers listeners, inspects process ancestry and working directories, reads Git and application-manifest evidence, probes HTTP/HTTPS behavior, persists aliases atomically, and runs a loopback-only reverse proxy.

Safe stop is intentionally narrower than `kill -9`: Docker, other-user, shared-runtime, and unattributed targets are refused. Eligible targets receive an identity-bound plan token, are revalidated immediately before `SIGTERM`, and count as stopped only when their listeners are actually gone. Force stop is not implemented.

## Build the current v1.0 candidate

Building requires Go and Xcode Command Line Tools. The resulting app is self-contained and does not require Python, Node.js, npm, Homebrew, Docker, or a separate proxy at runtime.

```bash
git clone https://github.com/Popcornnnnnnnn/port-tools.git
cd port-tools
native/trial/build.sh
open "native/.build/Port Tools.app"
```

Verify the bundle and its critical runtime paths:

```bash
python3 native/trial/verify.py
```

## v1.0 boundary

The current candidate is deliberately local and conservative:

- macOS 14 or later;
- IPv4/IPv6 loopback proxy on an unprivileged port;
- no `/etc/hosts` edits, trusted local CA, or ports 80/443;
- no privileged helper and no force termination;
- no claim that code-level tests replace real menu-bar interaction testing.

## Engineering notes

- [Product requirements](docs/PRD-v0.1.md)
- [Architecture decision](docs/ADR-0001-production-architecture.md)
- [Technical spike](docs/technical-spike.md)
- [Packaging requirements](docs/packaging-requirements.md)

Port Tools v1.0 is approaching its first public release. Issues and early feedback are welcome.
