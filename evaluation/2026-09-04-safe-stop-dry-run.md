# Safe-stop dry-run decision record

Date: 2026-09-04  
Status: Read-only policy prototype passing; real termination not authorized or tested

## Implemented boundary

`port-tools stop <service-id> --dry-run` resolves the service from a fresh scan,
then creates a human-readable or JSON stop plan. The command never calls
`kill(2)` and its output always includes `signalSent: false`. Invoking `stop`
without `--dry-run` is rejected before a service scan is performed.

## Eligibility policy

A target is eligible for a future graceful stop only when all of these are true:

- the scanned owner and current PID owner are the current macOS user;
- the PID still exists and its start time and command match the fresh scan;
- a single Git project establishes application ownership;
- the target is not a Docker-published service or recognized shared/system runtime.

The listener PID is the root of the current prototype's stop scope. Descendants
are direct-signal candidates only when their current owner and Git project match
the root. Other-user, cross-project, and unverified descendants are listed as
exclusions. The proposed order is deepest eligible descendants first, then the
root PID, using `SIGTERM` only. `SIGKILL` is explicitly unavailable in this
action and requires a separate future action and confirmation.

## Evidence

The unit suite passes 25 tests, including dedicated cases for nested process
trees, other-user refusal, Docker refusal, unattributed/shared-runtime refusal,
cross-project descendant exclusion, listener verification targets, and reused
PID identity rejection.

A live read-only run against a current-user Vite service produced an eligible
plan for exactly its listener PID and `127.0.0.1:4317`. The plan reported
`signalSent: false` and `forceAllowed: false`. A subsequent `lsof` check showed
the same PID still listening on the same port. No process was started, stopped,
or signalled during this validation.

## Deliberately unproven

- graceful shutdown behavior and timeout handling;
- listener-release verification after an actual signal;
- wrapper-process ownership above the listener PID;
- force-stop behavior;
- Docker container stop behavior.

The next acceptance step may test `SIGTERM` only against disposable fixtures.
It remains behind the explicit product-owner confirmation required by issue #6.
