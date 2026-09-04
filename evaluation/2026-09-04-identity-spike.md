# Project and process identity spike

Date: 2026-09-04  
Status: Identity acceptance matrix passing

## Result

The scanner correctly handled eleven identity scenarios across the disposable
fixture matrix:

| Fixture | Protocol result | Identity result |
|---|---|---|
| Static HTTP | confirmed Web | Git project from listener cwd |
| TCP echo | non-Web | Git project retained without changing protocol classification |
| Self-signed HTTPS | confirmed HTTPS | Git project from listener cwd |
| Vite/HMR | confirmed Web | Git project from listener cwd |
| Shell-wrapper child | confirmed Web | project recovered from absolute script path while cwd was `/private/tmp` |
| Primary worktree | confirmed Web | repository `worktree-main`, branch `main` |
| Feature worktree | confirmed Web | same repository, separate `worktree-feature`, branch `fixture-feature` |
| Docker-published nginx | confirmed Web | Docker container plus Compose working-directory project evidence |
| Monorepo package app | confirmed Web | Git worktree plus nearest `package.json` app root and package name |
| Ambiguous two-project command | confirmed Web | no selected project; both candidate roots retained |
| Unlabeled Docker nginx | confirmed Web | container identity retained; host runtime project explicitly rejected |

## Stable identity evidence

The primary worktree fixture was first run on port 51744 and then restarted on
51747 with a different PID. Its transient service ID changed from
`3d21191c7139` to `37e91d175192`, while its project-group ID remained
`e560202f6ec6`. This demonstrates the intended split between a live listener
identity and the stable project/worktree identity.

The two worktree fixtures share one `commonGitDirectory` and repository name,
but have different worktree roots, branches, and group IDs. In the inventory
they appear as two cards for the same repository with different branch/worktree
context, rather than as unrelated projects or one merged process list.

## Wrapper and Docker evidence

The shell wrapper's listening Python child had cwd `/private/tmp`; its command
contained the absolute fixture script path. The scanner recovered the
`port-tools` repository from that path and recorded `projectEvidence` as
`command-path`. Multiple distinct repository paths are not silently resolved:
the record becomes `ambiguous-command-path` and retains all candidate roots.
The managed ambiguity fixture confirmed this end to end with a live HTTP service
whose command references exactly two disposable Git projects.

Application identity is stored separately from Git/worktree identity. Vite,
Next.js, and the nested monorepo fixture resolve their nearest `package.json`;
the monorepo fixture is labeled `@port-tools/monorepo-web` while retaining the
outer `port-tools` worktree. Group identity prefers this application root, so
sibling apps in one worktree do not collapse into one card.

On this Mac, the Docker-published listener was owned at the host level by
`OrbStack Helper`, whose cwd happened to point at an unrelated `stationControl`
checkout. Trusting lsof cwd would therefore misattribute the service. Docker
inspection associated port 51746 with the exact container, and the standard
Compose `com.docker.compose.project.working_dir` label supplied the project
root. The resulting management source is `docker`, not OrbStack or an unmanaged
host process.

The unlabeled Docker fixture proved the negative policy: port 51753 retained
its container ID, name, image, and `management.source=docker`, while its project
remained null with `projectEvidence=docker-unattributed`. The unrelated host
runtime project is retained only as raw diagnostic evidence and is never used
for grouping, naming, or safe-stop eligibility.

## Timing and cleanup

A full scan of the current Mac with all fourteen fixtures completed in 3.8
seconds, below the five-second discovery target for this spike. All fixture
processes and three Docker containers were stopped, ports 51739 through 51753
were verified free, and the generated
`.runtime` directory was removed. OrbStack briefly retained its forwarding
listener after the container stopped; cleanup now waits for observed port
release instead of treating the Docker command result as completion. The shared
`nginx:alpine` image cache is intentionally not deleted because it may be used
by unrelated projects.

## Deferred management integrations

launchd and Homebrew ownership are not yet part of the machine-readable
management record. They are explicit future management-source integrations,
not reasons to guess project identity from a shared host process. The current
acceptance rule remains conservative: surface the service and its evidence,
but withhold destructive eligibility when ownership is ambiguous.
