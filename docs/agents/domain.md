# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root
- **`docs/adr/`** — read ADRs that touch the area you're about to work in

Neither exists yet in this repo. Proceed silently — don't flag their absence, don't suggest creating them upfront. The `/domain-modeling` skill creates them lazily when terms or decisions actually get resolved.

## File structure

Single-context repo:

```
/
├── CONTEXT.md
├── docs/adr/
└── docs/prd.md
```

## Use the glossary's vocabulary

When your output names a domain concept, use the term as defined in `CONTEXT.md` once it exists. Until then, follow the vocabulary already established in `docs/prd.md` (e.g. CFI, 直排/橫排, 避頭尾).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding.
