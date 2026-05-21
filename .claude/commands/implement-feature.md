---
name: implement-feature
description: Guided multi-domain feature implementation with agent delegation
disable-model-invocation: true
---
Implement: $ARGUMENTS

## Process

1. **Read CLAUDE.md** before touching any file.

2. **Identify ALL domains touched** — map to tags:
   - SERVER — services, data mutation, MarketplaceService
   - CLIENT — controllers, client logic
   - UI — ScreenGui binding, SpringV2 animations, UIAnimator
   - NETWORKING — bridges, client↔server payloads
   - REPLICATION — Replica, SetValue, ListenToChange
   - VFX — Fireworks, Shake, camera effects
   - SOUND — audio playback
   - CONFIG — shared configs, types, constants, ProductIds
   - LIFECYCLE — Janitor cleanup

3. **Phase 1: Data contract** — spawn first:
   - `server-handler` for service logic
   - `networking-specialist` for bridges
   - `config-balancer` for configs/types
   - `replication-specialist` for Replica paths

4. **Phase 2: Client consumption** — after data contract:
   - `client-controller` for controllers
   - `ui-controller` for UI
   - `animation-vfx` for effects
   - `sound-specialist` for audio

5. **Phase 3: Cleanup review** — always:
   - `janitor-lifecycle` for connection/cleanup audit

6. **Summarize:** changed files, behavioral impact, networking implications, cleanup implications.
