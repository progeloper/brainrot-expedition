Current owner scope: [Phase 14 revision 2](phase14/evidence/completion/revision2_20261024/Owner_Prompt_Revision2.txt), with the owner's subsequent current-loop clarification: shooting to sleep, then explicit pickup/transport/bank. Obsolete capture/reel gates and reports do not override this direction. Current completion status and unresolved assertions are recorded with that revision's installed evidence.

# Brainrot Expedition

Vehicle-based Roblox hunting and collection experience.

Current Development scope: independent owner-operated one-seat carts in shared multiplayer servers. Human shared-cart co-op is deferred. Equipped-brainrot teams, purchased slots, formations and their effects remain part of the solo cart experience. See [current scope](docs/solo-removal/Current_Roadmap.md) and [verification report](docs/solo-removal/Implementation_Report.md).

## Environments

- Development: local and unstable development.
- Sandbox: integrated private testing.
- Production: public release.

Each environment uses a separate DataStore prefix.

## Required tools

- Roblox Studio
- Git
- Visual Studio Code
- Rokit
- Rojo
- StyLua
- Selene

## Tool installation notes

On Intel macOS:

- Rojo is managed with Rokit.
- Selene may be installed through Homebrew.
- StyLua may be installed through Homebrew or Rokit.

All tools must be available on the terminal PATH.

## Start Rojo

```bash
rokit install
rojo serve
```


## Canonical project and Phase13

This repository at `/Users/noahodukoya/development/Roblox/BrainrotExpedition` is the active project. Runtime source is `src/`; Rojo uses [default.project.json](default.project.json). The previously reconciled Source21 code and streaming configuration have been incorporated here. `phase13/stage` is a frozen checkpoint.

[Reconciliation report](phase13/remediation/2026-10-19/reconciliation/2026-10-20_Canonical_Development/Reconciliation_Report.md) records exact changes, retained map-art variants and the verified pre-change backup. [Latest bounded continuation](phase13/remediation/2026-10-19/continuations/2026-10-20_Source21_Bounded/Source21_Bounded_Continuation_Report.md) records the unresolved native DataStore HTTP401 and completed execution-QA cleanup. Phase13 is incomplete; no performance, purchase or production acceptance is inferred from this filesystem reconciliation.

Rojo preserves unknown native instances. A source-only Rojo build does not contain the complete native map/art and must not replace the open DEV place. Historical QA tools are not normal boot entry points.
