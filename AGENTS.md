# Code Review Rules

- Review the exact source contribution and affected context against the original acceptance criteria. Support findings with a concrete location, evidence, and practical impact.
- Verify assumptions, make the smallest complete change, reuse existing patterns, and preserve unrelated work, data, and permissions.
- Keep listener/process identity binding and evidence-based classification intact. Failed probes and JSON errors do not prove that a listener is permanently API-only.
- Run relevant isolated regression checks. Distinguish source inspection, passing tests, pending CI, and actual runtime acceptance; never report a failed or unexecuted check as passed.
- Source delivery does not authorize installation, release, deployment, account access, or device operations. Follow `docs/releasing.md` for separately authorized releases.
