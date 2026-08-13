# ms_alert.lua — comment triage

Buckets: 1=section marker (keep), 2=rationale (strip→stage in ms_alert.md),
3=historical (discard), 4=terse label (keep/trim), 5=TODO (keep).

| Line | Bucket | Action | Comment |
|------|--------|--------|---------|
| header | 3 | discard | `-- MsAlert — converted from a Spoon; Spoons/ is reserved for plugins.` (already removed in working tree) |
| 10  | 4 | keep | Animation settings read from theme at runtime |
| 87  | 2 | strip→stage | screenSaver+1 curtain reasoning |
| 144 | 4 | keep | Octane: snap to final state |
| 197 | 4 | keep | Forward-declared so redraw's closure can reference it |
| 218 | 4 | keep | Expire every toast on screen right now, animated (fn label) |
| 219 | 2 | strip→stage | exit-paths: fade vs mid-air delete |
| 220 | 4 | keep | Backwards over the queue because dismissEntry removes as it goes |
| 227 | 2 | strip→stage | `_sealed` seal explanation |
| 273-274 | 4 | keep (trim) | dismissByIdAnimated label — trim the trailing "so a fresh alert can replace it" |
| 356 | 4 | keep | Suppress all toasts until loading completes |
| 359 | 2 | strip→stage | exit-cleared `_sealed` gate |
| 367 | 4 | keep (trim) | Auto-replace label — trim to the label |
| 415 | 2 | strip→stage | append-order reasoning |

All section markers (`-- X --` / `-- END --`) kept verbatim.
