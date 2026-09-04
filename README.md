# port-tools

`port-tools` is a proposed local development control plane for discovering forgotten web servers, understanding which project owns them, assigning stable `*.localhost` URLs, and stopping them safely.

The project is currently in discovery and technical-spike stage. Product scope and acceptance criteria live in:

- [`docs/PRD-v0.1.md`](docs/PRD-v0.1.md)
- [`docs/technical-spike.md`](docs/technical-spike.md)

The first read-only scanner prototype is runnable now:

```bash
bin/port-tools scan
bin/port-tools scan --json
bin/port-tools scan --all-web
bin/port-tools scan --json --all
```

The default view shows only Web endpoints with developer-project evidence.
Protocol classification and developer relevance are intentionally separate in
the JSON contract; an application can expose a valid local HTTP endpoint
without being a development website the user wants to manage.

No privileged helper, trusted certificate authority, background service, or process termination behavior should be introduced until the corresponding decision gate in the PRD is resolved.
