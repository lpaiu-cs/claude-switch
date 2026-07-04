# examples/

## `setup-shared.ps1` (+ `setup.cmd`)

A **personal, one-time migration** script — the author's own. It is **not required for a
fresh install** of `claude-switch` and is kept here only as a reference.

It assumes a specific starting state: a single logged-in account sitting in a profile named
`main`. Running it will:

1. Move the heavy, account-neutral folders (`vm_bundles`, `claude-code`, `claude-code-vm`)
   into the shared store (`ClaudeShared`), linked back with junctions.
2. Relabel that account `main` -> `work`.
3. Create a fresh empty `main` profile for a second account.

It is idempotent and aborts if the starting state doesn't match (so it won't clobber data),
but because it hard-codes the `main` -> `work` intent it isn't meant for general use.

**For normal setups**, you don't need this. To (re)link shared infrastructure into every
profile at any time, use the main tool instead:

```powershell
.\claude-switch.ps1 -Setup
```
