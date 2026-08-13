# MsCompiler — visual-macro → Lua compilation

Staged rationale from `mac/lib/ms_compiler.lua`. Source material for the phase-4
navigable docs. Security-relevant invariants are flagged **[SECURITY]** — the
code keeps a terse guard label at each site; the full reasoning is here.

## Tool bindings (`__toolRef`)

A parameter can be wired to a live "tool" (an authored setting) instead of a
literal. The builder sends such a binding as the table `{ __toolRef = "settingKey" }`;
it compiles to a `ms.settings.get("settingKey")` call so the macro reads the
tool's current value at run time — the whole point of the feature is to make a
macro configurable from the Settings panel without editing and reloading its
source. Anything else is not a binding.

**[SECURITY]** The key is validated as an identifier so a hostile JSON payload
can never break out of the string into arbitrary Lua.

A numeric argument may instead be a tool binding. The plain numeric emitters
(waits, camera deltas, coordinates) drop values in with `tostring()` rather than
`serialize()`, so they need their own funnel to honour a binding; it returns a
Lua expression string.

## Empty-string identifiers

An unset identifier arrives from the builder as `""` (not nil), which is truthy
in Lua — `p.name or "v"` would keep the empty string and emit invalid code
(`local  = 1`). Fall back explicitly.

Same shape for conditions: an empty string is truthy and would emit `if  then`;
fall back to `true` so an unset condition is still valid code.

## Click / drag emission

A bound click count is always emitted (its value is unknown at compile time); a
literal one is only emitted when > 1, the pre-binding behaviour. Drags carry a
second point (start → end); emit x2/y2 whenever the step supplies them — the
recorder does for Drag ops — so the gesture round-trips instead of collapsing to
a click.

## Conditional block shapes

The visual canvas (ToolCanvas) is the canonical shape: it stores branches as
`step.then` / `step.else` / `step.body` and the condition in
`step.params.condition`. Older/hand-authored JSON used `step.condition` and
`step.then_steps` / `step.else_steps`. Read both, canvas first. `then`/`else` are
reserved words, so the canvas keys must be reached with bracket syntax rather
than dot access.

## "setting" blocks compile to an inert comment

A "setting" block is a reference to a globally-shared tool (an authored setting),
not a code action. Macros and tools are independent: the setting is defined once
in the Tools panel and read live via `ms.settings.get(key)`. So this emits only
an inert, single-line comment documenting which shared setting the macro uses —
never a re-definition.

**[SECURITY]** The key is identifier-validated and the label stripped of newlines
so nothing can break out of the comment into executable Lua.

## String quoting

**[SECURITY]** Quote a string as a Lua literal, escaping anything that could
break out of the generated source (the file is loaded, so an unescaped
quote/backslash/newline would be a syntax or injection hazard). Non-strings fall
back to an empty literal.

## Idempotent re-load / id purge

An in-session save calls the loader again after boot already registered the
visual macros. `ms.bind.define` appends to `ms.registry._defList`
unconditionally, so without purging first every save would duplicate the macro
in the bind list. Remember what was registered (the `{id, source}` sources list)
so the next re-load after a save/delete purges exactly those ids before the
compiled chunk re-defines them.

## Credits ownership (handwritten wins)

Handwritten credits win. The compiled chunk assigns `ms.macroMeta`; if the
handwritten pack already provided its own, lock it so the sandbox's `__newindex`
drops the visual write (see ms_core). A pure-visual profile (no handwritten
meta) leaves the flag false, so its meta lands and stays editable.

The visual pack's `ms.macroMeta` lives at `data.meta` in the JSON and is emitted
verbatim into the compiled file's `ms.macroMeta` table. When a handwritten
`ms_macros.lua` supplied credits, source the editor straight from the live
handwritten meta and flag it `owned`, so the panel shows it read-only instead of
maintaining a second, clashing set the runtime ignores. Writing to the visual
editor there would be silently ignored at load, so it refuses rather than persist
a value that never takes effect.

## Test Run

Compile only the step body (no `ms.bind.define` wrapper) and run it once in the
macro sandbox — the builder's Test Run button.

The run happens inside a coroutine, exactly as a bound macro does through
`ms.fn` — so `ms.wait` yields (and resumes on its timer) instead of
block-sleeping, and the test is a faithful preview of the real thing. Because the
run is async, the result is delivered through `onDone(ok, err)` rather than a
return value: compile/setup failures fire it synchronously, a real run fires it
when the coroutine finishes. `onDone` is optional; without it the macro still
runs, just with nowhere to report to.

Registering a context in `ms._coroContext` gives the run the same cancel/pause
hooks and dead-coroutine cleanup a bound macro gets. `xpcall` inside the body
catches errors across the yields (pcall/xpcall are yieldable in Lua 5.4) and
hands them to `done()`. An error escaping the coroutine body itself (not caught
by the inner xpcall) is surfaced rather than lost.
