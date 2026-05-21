---
name: trace-feature
description: End-to-end feature trace through all system layers without editing
disable-model-invocation: true
---
Trace this feature: $ARGUMENTS

## Output

1. **Entry point** — which init script, which input event
2. **Owning Service(s)** — which services in `Server/Services/`
3. **Owning Controller(s)** — which controllers in `Client/Controllers/`
4. **BridgeNet2 path** — which bridge in Bridges.luau, payload shape
5. **Replica path** — which SetValue calls, which ListenToChange listeners
6. **Cleanup/lifecycle** — which Janitor scope (character vs player)
7. **Sound assets** — which sounds involved
8. **VFX assets** — which effects (Fireworks, Shake, particles)
9. **Config files** — which configs, types, constants
10. **Likely edit points** — file + function name
11. **Regression risks** — what could break

Do NOT implement changes.
