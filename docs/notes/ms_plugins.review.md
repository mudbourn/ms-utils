# ms_plugins.lua — comment triage

Buckets: 1=section marker (keep), 2=rationale (strip→stage in ms_plugins.md),
3=historical (discard), 4=terse label (keep/trim), 5=TODO (keep).

| Line (orig) | Bucket | Action | Note |
|------|--------|--------|------|
| 1 | 1 | keep | module title marker (+ pointer to notes) |
| 2-29 | 2 | strip→stage | proxy/teardown design essay |
| 36-38 | 2 | strip→stage | `ms.plugins` field shape |
| 45 | 1 | keep | Helpers marker |
| 53 | 4 | keep | "Removes the first identity match, in place" |
| 62 | 1 | keep | Recording Proxy marker |
| 63-66 | 2 | strip→stage | subProxy forward/override rationale |
| 78-85 | 2 | strip→stage | wrapped-surfaces rationale |
| 89-91 | 2 | strip→stage | bind dispatcher reasoning |
| 116-117 | 2 | strip→stage | key handle reasoning |
| 126-129 | 2 | strip→stage | mouse identity-check reasoning |
| 142-144 | 2 | strip→stage | scrollBind identity-check reasoning |
| 204-209 | 2/4 | trim + stage | keep one-line load() label; stage Guardian rationale |
| 225-228 | 2 | strip→stage | plugin env `_G` fall-through reasoning |
| 234-235 | 2 | strip→stage | package.preload seam reasoning |
| 248-250 | 2 | trim + stage | keep one-line "replay mid-load throw"; stage detail |
| 265-266 | 2 | trim | shortened to one-line pcall label |
| 277-284 | 2 | trim + stage | keep one-line unload label; stage 3-step detail |
| 315-316 | 2 | strip→stage | markDirty reasoning |
| 322-325 | 2 | trim + stage | keep one-line apply label; stage detail |
| 337-339 | 2 | trim | shortened to one-line sweep label |
| 349 | 1 | keep | END marker |

Table broken: L231 `{ __index = _G, __newindex = _G }`.
