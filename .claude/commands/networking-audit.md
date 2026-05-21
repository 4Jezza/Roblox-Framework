---
name: networking-audit
description: Audit networking for validation, payload shape, authority, and cleanup issues
disable-model-invocation: true
---
Audit: $ARGUMENTS

## Check for:
- Duplicate or bypassed network paths (raw RemoteEvents instead of BridgeNet2)
- Payload shape drift (multi-param `Bridge:Fire` instead of single table)
- Missing server-side validation on `Bridge:Connect` handlers
- Client-authoritative gameplay outcomes
- Replica listener misuse (yielding inside ListenToChange/ListenToWrite)
- Missing Janitor cleanup on bridge connections
- KnitInit inter-service calls (only allowed in KnitStart)
- Profile.Data containing non-serializable values
- Missing Ser usage at data boundary
- Receipt processing not idempotent

## Return findings grouped by severity:
- **CRITICAL** — data corruption, exploitability, session loss
- **WARNING** — architectural drift, replication desync, cleanup leak
- **INFO** — style or maintainability concern
