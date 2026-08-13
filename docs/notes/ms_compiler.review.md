# ms_compiler.lua — comment triage

Buckets: 1=section marker (keep), 2=rationale (strip→stage in ms_compiler.md),
3=historical (discard), 4=terse label (keep/trim), 5=TODO (keep).

Approach: this module's rationale is largely security invariants (Lua injection
via generated source). Each such site keeps a one-line `[SECURITY]` guard label
in code; the full reasoning is staged in ms_compiler.md.

All ~20 non-marker blocks were rationale (bucket 2). Trimmed to one-line labels
in code and staged in full. Section markers unchanged. One inline table broken
(L540 `{ id, source }`). luac clean.

Key `[SECURITY]` labels kept inline: `toolRef` (identifier validation),
`setting` block (identifier + newline strip), string `quote` (escape for loaded
source).
