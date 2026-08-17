# MsGuardian

Pre-load integrity check. A lib module, but not one `ms_core` requires:
`mac/init.lua` calls it, it verifies hashes, and only then does it `dofile`
`ms_core.lua`. It runs before `ms` exists and is what loads core. See DOCS_MAC.md
section 20 for the full security model, and TRUST.md.

## Public key

The embedded RSA-2048 public key verifies `MANIFEST.json` and the per-file
manifest signatures. It must match `ms._updatePublicKey` in `ms_core.lua` and
`PUBLIC_KEY` in `ms_registry.lua`.

## Batched hashing (the boot-hang fix)

`_hashFile` spawns one `shasum` subprocess per file. Guardian runs at pre-load
and hashes every tracked file twice (trusted-manifest check plus signed file
manifest check), so a naive boot is 60-100 synchronous process spawns before
anything else can run, and on a slow or busy machine that spawn contention alone
is a multi-second freeze. That was the long startup/restart hang.
`_hashFilesBatch` computes the identical hashes in one `shasum` invocation. A
file `shasum` cannot read simply has no output line, so it is absent from the
map, which callers treat as a nil hash. `shasum` prints `<hash>  <path>` (two
spaces in text mode, `<hash> *<path>` in binary mode); the path is echoed
verbatim from the argument and may contain spaces, so parse everything after the
separator.

## Trusted-manifest formats

`_readTrustedManifest` handles both the old format (a single hex hash for
`ms_core.lua`) and the new JSON manifest (`{relativePath = hash64}`).

## Allowlist checks vs the Spoons added-file check

Every hash check here is an allowlist: it hashes the files it expects and says
nothing about files it has never heard of. That is fine for the dirs mudscript
ships, because deploy replaces those wholesale and a stray there is inert.
`Spoons/` is the exception: it is the one dir whose contents are third-party code
that Hammerspoon will happily load, so an *added* `.spoon` is the entire threat,
and no hash of known files will ever see it. The added-file check is deliberately
NOT widened to all tracked dirs: a `.DS_Store` or an editor `.bak` would then
hard-block boot, and a Guardian that cries wolf over Finder detritus is one
people switch off.

## The plugin ledger never seeds from disk

The ledger (`.ms_plugin_ledger.json`) is written by `ms.package.install` when a
plugin passes the trust gate, so "in the ledger" means "arrived through the front
door". A missing ledger with plugins on disk blocks. It deliberately does not
seed from what is already installed: that would make deleting one file the way to
launder any `.spoon` into a trusted state, which is exactly the hole the
trusted-hash manifest has and not one worth reproducing. The cost is that
installs predating this check must re-import their plugins once. With no plugins
installed there is nothing to vouch for, so an empty ledger is written and boot
continues. A tree that no longer hashes to its ledger record was edited in place
(same front door, different code) and gets the same `unknown` answer. The
`noledger` and `unknown` blocks are distinct screens: the likeliest cause of
`noledger` is an install predating the ledger, not tampering, so telling someone
their own plugin is "unrecognized" would send them after the wrong problem.

## Spoon-tree digest must match ms_package

`_hashSpoonTree` produces a deterministic digest: every file's hash, path-sorted.
Two invariants keep it stable for the same bundle and MUST stay byte-identical to
`spoonTreeHash` in `ms_package.lua`:

- `LC_ALL=C` pins the sort collation so it does not vary with the process locale
  (C on GUI launch vs en_US on terminal launch).
- The `._*` and `__MACOSX` excludes drop AppleDouble metadata a Finder-"Compress"
  package carries in; macOS reaps those files out of the bundle later, so hashing
  them makes the digest drift after install. They are inert, so excluding them is
  safe.

Either drift trips the Unrecognized Plugin block on a legitimately installed
plugin.

## Signed MANIFEST.json is the sole authority for seeding trust

`_signedManifestConfirms` is the only thing allowed to (re-)seed trust: without
it, the files on disk are just files and hashing them proves nothing. It requires
the on-disk `ms_core.lua` hash to match `MANIFEST.json`'s `sha256` AND the
manifest signature to verify. `_seedTrustedFromDisk` does no verification of its
own; callers MUST establish trust first.

## File-manifest signature: jq -c -S, minified, no trailing newline

The per-file manifest signature covers minified JSON of `{version, generated,
files}` matching what CI signs. Use `jq -c -S` to guarantee sorted keys;
`hs.json.encode` does not sort and would produce a different payload. CI signs
the JSON directly (not a hash of it), and its `jq -c -S` output ends in a
newline, which is stripped before verifying so the message matches what was
signed. (Contrast the registry index, which signs *with* the trailing newline;
match each signer exactly.)

## Update & Repair

`_repairViaUpdate` downloads the latest signed bundle, verifies `MANIFEST.json`,
backs up then overwrites, and reloads. It runs with no `ms.*` namespace (Guardian
loads before core), using only raw `hs.*`. `replaceList` MUST include `lib/`:
every extracted module, Guardian included, lives there now, so an update that
skipped it left the install half-old with no sign anything had gone wrong. The
template list is copied only when the destination is absent, so user data is not
clobbered.

## Block screen

`_showGuardianBlock` shows the blocking webview (with a dialog fallback). A `spec`
retitles the screen and replaces its rows, warning copy and buttons; omitted, it
stays the integrity screen driven by the two hashes. The error sound reads from
`sounds/defaults/`, not `sounds/Default/` (the latter never existed, which made
the block screen silent whenever custom theming was off). `keepBlocked` quits
Hammerspoon outright rather than leave it half-dead (menubar alive, no core), so
the user makes a clean choice: repair, or no Hammerspoon. The window position is
tracked in Lua (`_guardianPos`), not read back from `frame()`, so it survives the
drag. `_safeShow` is a local copy of `ms.safeShow` because the global `ms` does
not exist yet.
