# Direction 2 — Attention-first triage

## Hypothesis

People returning to local development after several hours or days do not first need a project inventory. They need to know which verified Web services deserve attention, and which healthy services are safe to open immediately.

## Information hierarchy

1. `Needs attention`: LAN exposure and likely-forgotten processes, with an explicit Review action.
2. `Ready to open`: verified Web apps, with the healthy reassurance kept visible.
3. Project, branch, port, and age remain supporting evidence rather than the primary navigation.

## Interaction model

- No project accordions or disclosure arrows.
- Attention rows use an explicit `Review` button.
- Healthy rows open an inspector when the row is clicked.
- The inspector provides Open, Copy, Name/Rename, evidence, and safe-stop review.
- This browser prototype uses fixed sample data and simulates actions; it never stops a real process.

## Trade-off

This direction makes cleanup and risk review faster, but users who think primarily in repositories may find it less scannable than Direction 1.
