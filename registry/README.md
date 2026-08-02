# Package Registry Index

`index.json` is the registry: one in-tree, signed document listing every
publishable package. Binaries are **not** kept here — each entry points at a
release asset. The index stays small enough to review in a diff.

The client is `mac/lib/ms_registry.lua`. It fetches this file from the default
branch, verifies the signature, and caches it. It never installs; it hands
paths to `ms.package.install`.

## Entry shape

```json
{
  "id":          "aurora-theme",
  "type":        "theme",
  "name":        "Aurora",
  "version":     "1.2.0",
  "author":      "mudbourn",
  "description": "Cool-toned dark theme.",
  "website":     "https://github.com/mudbourn/ms-utils",
  "sha256":      "<64-hex sha256 of the .mspkg>",
  "url":         "https://github.com/mudbourn/ms-utils/releases/download/v1.2.0/aurora.mspkg",
  "size":        20481,
  "requires":    "1.4.0",
  "trust":       "trusted"
}
```

Rules the client enforces when reading an entry. **A row failing any of these
rejects the entire index**, exactly as a bad signature does — a skipped row
would fail invisibly, leaving a package missing from the library with no way to
tell whether that was intended. Validate before signing:

- `sha256` must be 64 hex characters. It is checked against the downloaded
  bytes before the path is handed back.
- `type` must be a known `ms.package` type (`macro`, `theme`, `sound`,
  `plugin`, `profile`).
- `url` must be `https` on a GitHub host. An index entry is data, not
  instruction; it cannot redirect the downloader anywhere else.
- `trust` is `"trusted"` only for author-published packages. Anything else,
  including a missing field, reads as `"community"`.
- `id` and `sha256` must each be unique. A duplicate is ambiguous about which
  row's trust applies, so it is rejected rather than resolved by ordering.

`ms.registry.status().error` names the offending row, so a rejected index says
which entry broke it.

## Publishing

Merging an edit does not publish it. An index that lands on `main` still
carries the previous signature, which no longer covers it, so the client
discards it whole and every install falls back to zero entries. **An edit is
live only once it has been re-signed.**

1. Upload the `.mspkg` as a release asset and note its `sha256` and size.
2. Add the row to `entries` and commit. Push validation runs on every change
   to this file — check it before assuming the edit is good.
3. Run the **Sign Registry** workflow from the Actions tab with *sign*
   checked. It validates, signs, verifies its own signature against the key
   the client carries, and commits the result back.

Validate locally before committing — no key needed:

```bash
bash mac/bin/registry_sign.sh
```

Holders of the signing key can also sign locally with
`bash mac/bin/registry_sign.sh --sign --key <file>`, but the workflow is the
normal path: `MS_SIGNING_KEY` lives in repository secrets.

### What the signature covers

The minified, key-sorted JSON of the document **without** the signature field,
signed with `MS_SIGNING_KEY` — the same RSA-2048 key Guardian verifies
`MANIFEST.json` against:

```bash
jq -c -S '{formatVersion, generated, entries}' registry/index.json
```

`jq -c -S` is required: the client rebuilds this exact byte sequence, and
`hs.json.encode` alone does not sort keys.

`generated` is stamped by the signer, not by hand. It is inside the signed
payload, so an empty or missing value is not merely untidy — `hs.json.encode`
omits an absent key where `jq -c -S` writes an explicit `null`, and the two
byte sequences will not match. The validator rejects a signed document whose
`generated` is empty for that reason.

## Where the index comes from at runtime

`ms_registry.lua` tries three sources in order, and **signature-checks all
three** — a local copy is not trusted for being local:

| Source | Path | Notes |
| --- | --- | --- |
| network | `raw.githubusercontent.com/.../registry/index.json` | 6-hour TTL |
| cache | `data/ms_registry_cache.json` | last good fetch |
| bundled | `data/registry_index.json` | ships in the release archive |

The bundled copy is what a fresh install with no network reads. It is the
signed index as of build time, so it goes stale rather than wrong.

An index whose signature does not verify is discarded whole — not served with
its trust downgraded. A forged document does not get to choose which of its own
claims are believed. The client then reports zero entries and answers
`"unsigned"` for every hash, which is the same behaviour as no index at all.
