# MsRegistry — signed package index client

Staged rationale from `mac/lib/ms_registry.lua`. Source material for phase-4
docs. Security invariants are flagged **[SECURITY]**; the code keeps a terse
guard label at each site.

## What it is

Fetches, verifies and caches the signed package index, and answers two questions
about it: "what packages exist?" and "is this hash one of ours?"

It deliberately does not install anything. `download` hands back a path on disk
and stops; the caller passes that path to `ms.package.install`. Keeping the two
apart means a compromised index can, at worst, offer a package the normal
verify → trust → install path still has to accept.

The index is a single JSON document living in-tree at `registry/index.json`,
served from the repo's default branch. Package binaries are release assets, so
the index stays small and reviewable in a diff.

## Trust model

Trust comes from the index and only from the index:

- `trusted` — the hash is listed and the entry is author-published
- `community` — the hash is listed and the entry is third-party
- `unsigned` — the hash is not listed, or there is no usable index

`unsigned` is the answer for every degraded case — no cache, no network, a
malformed document, a bad signature. None of those raise; a registry that is
simply absent must leave the rest of mudscript working, so every path ends in an
empty index rather than an error. Anything not explicitly marked author-published
is community. An unsigned index can never elevate anything, and a hash nobody
listed is "unsigned" — never an error, never a nil.

## [SECURITY] Signature verification

The index signature covers `jq -c -S '{formatVersion, generated, entries}'`
signed with the same RSA-2048 key Guardian checks MANIFEST.json against. An index
whose signature does not verify is discarded whole rather than served with its
trust stripped: a forged document should not get to choose which of its own
claims we believe.

The public key must match `_publicKey` in `lib/ms_guardian.lua` and
`ms._updatePublicKey`.

**Rebuild the signed bytes exactly.** CI signs the minified, key-sorted JSON of
the payload directly, so we rebuild exactly that byte sequence with `jq -c -S`
before verifying. `hs.json.encode` alone will not do — it does not sort keys.

**`generated` must be present and non-empty** in any document claiming a
signature. A nil here is dropped by `hs.json.encode`, where the signer's
`jq -c -S '{formatVersion, generated, entries}'` writes an explicit null — two
different byte sequences over the same document, so the signature fails and the
index is discarded whole. That reads as a bad signature and sends you hunting a
key problem that is not there. `bin/registry_sign.sh` refuses to produce such a
document; this is the other half of that contract.

**Verify the jq output VERBATIM, including its trailing newline.** The signer
signs `jq -c -S … > msg.bin` as-is, so the signed bytes end in `"\n"`. Stripping
it made the message one byte short of what was signed, and RSA rejected every
index as "bad signature" — the library then served zero entries. Do not trim;
match the signer's bytes exactly. (See project memory: registry-signature-trailing-newline.)

## [SECURITY] Download host allowlist

Only http(s), and only hosts we publish from. An index entry is data, not
instruction: it does not get to point the downloader anywhere.

`download` fetches an entry's binary to a temp path and verifies its hash against
the index before handing the path back. It does not install — the caller passes
the path to `ms.package.install`, which re-verifies with `trustLookup` on its own
terms.

## Shared `ms.registry` table

`ms.registry` is shared: `ms_core.lua` creates it as the bind registry
(`_defs`/`_defList`) at boot, and this module adds the package-registry API onto
that same table. Reassigning it here would silently drop every bind definition,
so extend in place. The two namespaces do not overlap — binds own the
`_`-prefixed internals, the package client owns the rest. (See project memory:
ms-registry-shared-table-clear-in-place.)

`_index` is always a table of the empty shape, never nil, so every reader can
index it without a guard.

## Row validation

A bad row rejects the whole document, same as a bad signature. The alternative —
skipping it — fails invisibly: the package simply is not in the library and
nobody can tell whether that was intended. Rows only ever land here through a
signed, reviewed commit, so a malformed one is a publishing mistake worth failing
loudly on (returns nil plus a reason naming the offending row).

A profile row may carry a lightweight components summary (which slices the one
asset offers) so Browse can present install choices without downloading first.
Kept verbatim; the authoritative file map still lives in the package manifest.

A duplicate id is ambiguous about which row's trust applies, so it is rejected
rather than resolved by ordering.

`trustLookup` also checks the declared type: the index vouches for a hash under a
declared type, so a package claiming to be something else is not the thing that
was listed.

## Load / refresh

On boot, load whatever is on disk now (cache first, then the copy that shipped
with the install) so `trustLookup` answers immediately; both are
signature-checked, and neither failing is worth surfacing because the next
`refresh()` is the real answer. The network refresh is best-effort and silent:
a network failure is not fatal — whatever we already had, cached or bundled,
stays serving.
