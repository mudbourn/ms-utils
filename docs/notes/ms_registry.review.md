# ms_registry.lua — comment triage

Buckets: 1=section marker (keep), 2=rationale (strip→stage in ms_registry.md),
3=historical (discard), 4=terse label (keep/trim), 5=TODO (keep).

- **Header essay (L1-30)** → staged; replaced with a one-line pointer.
- **Security invariants** → kept as one-line `[SECURITY]` guards inline, full
  reasoning staged: public key match, host allowlist, `jq -c -S` byte rebuild,
  `generated` non-empty, verbatim trailing newline, type-vouch in trustLookup.
- **Rationale blocks** (shared-table, `_index` non-nil, bad-row-rejects,
  duplicate-id, components summary, network-not-fatal, load/refresh) → trimmed to
  one-line labels; detail staged.
- **API-signature labels** kept: `opts = {…}`, `cb(ok,err)`, installIndex,
  download, state — these name the surface, not rationale.
- One inline table broken: L214 `_index = { formatVersion, generated, entries }`.
  (The `opts = { type, query }` at L300 is a comment, left as-is.)

luac clean; section markers byte-identical to HEAD.
