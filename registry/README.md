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

## Signing

The signature covers the minified, key-sorted JSON of the document **without**
the signature field, signed with `MS_SIGNING_KEY` — the same RSA-2048 key
Guardian verifies `MANIFEST.json` against.

```bash
UNSIGNED=$(jq -c -S '{formatVersion, generated, entries}' registry/index.json)
printf '%s' "$UNSIGNED" > /tmp/idx_msg.bin
openssl dgst -sha256 -sign /tmp/key.pem -out /tmp/idx_sig.bin /tmp/idx_msg.bin
SIG=$(base64 -w0 /tmp/idx_sig.bin)
jq --arg sig "$SIG" '.signature = $sig' registry/index.json > /tmp/idx.json
mv /tmp/idx.json registry/index.json
```

`jq -c -S` is required: the client rebuilds this exact byte sequence, and
`hs.json.encode` alone does not sort keys.

An index whose signature does not verify is discarded whole — not served with
its trust downgraded. A forged document does not get to choose which of its own
claims are believed. The client then reports zero entries and answers
`"unsigned"` for every hash, which is the same behaviour as no index at all.
