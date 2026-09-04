# Project and process identity spike

Date: 2026-09-04  
Status: Passing first end-to-end matrix; ambiguity fixture still pending

## Result

The scanner correctly classified and attributed eight disposable fixtures:

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

## Stable identity evidence

The primary worktree fixture was first run on port 51744 and then restarted on
51747 with a different PID. Its transient service ID changed from
`0dd88554f45e` to `40462f51f85c`, while its project-group ID remained
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

On this Mac, the Docker-published listener was owned at the host level by
`OrbStack Helper`, whose cwd happened to point at an unrelated `stationControl`
checkout. Trusting lsof cwd would therefore misattribute the service. Docker
inspection associated port 51746 with the exact container, and the standard
Compose `com.docker.compose.project.working_dir` label supplied the project
root. The resulting management source is `docker`, not OrbStack or an unmanaged
host process.

## Timing and cleanup

A full scan of the current Mac completed in 2.98 seconds, below the five-second
discovery target for this spike. All fixture processes and the Docker container
were stopped, ports 51739 through 51747 were verified free, and the generated
`.runtime` directory was removed. OrbStack briefly retained its forwarding
listener after the container stopped; cleanup now waits for observed port
release instead of treating the Docker command result as completion. The shared
`nginx:alpine` image cache is intentionally not deleted because it may be used
by unrelated projects.

## Remaining limits

- A Docker container without Compose working-directory metadata can be
  identified as a container but cannot yet be assigned confidently to a host
  project.
- Ambiguous command-path handling has unit coverage; a managed end-to-end
  ambiguity fixture remains to be added.
- Package/app-root detection below the Git worktree is not implemented yet.
- launchd and Homebrew ownership are not yet part of the machine-readable
  management record.
