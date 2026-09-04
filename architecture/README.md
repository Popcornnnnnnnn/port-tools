# Architecture spike

`spike/` proves the selected production bundle shape without becoming the MVP
implementation. It builds a native SwiftUI menu-bar executable plus a bundled
Go core, signs nested code and the outer app, and verifies a private Unix-socket
API.

The build requires an explicit `GO_BIN` path and Xcode command-line tools:

```bash
GO_BIN=/absolute/path/to/go architecture/spike/build.sh
python3 architecture/spike/verify_bundle.py
```

Generated output stays under the ignored `architecture/.build/` directory.
Build tools are developer/CI requirements only; the resulting app has no Go,
Python, Node, npm, Homebrew, or Docker runtime prerequisite.

This spike does not yet contain the production scanner or proxy. Those are
required to pass the existing behavior matrices before the architecture can be
called an MVP.
