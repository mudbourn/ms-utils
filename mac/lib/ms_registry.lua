-- ms_registry — Package Registry Client --
--
-- Fetches, verifies and caches the signed package index, and answers two
-- questions about it: "what packages exist?" and "is this hash one of ours?"
--
-- It deliberately does not install anything. `download` hands back a path on
-- disk and stops; the caller passes that path to ms.package.install. Keeping
-- the two apart means a compromised index can, at worst, offer a package the
-- normal verify → trust → install path still has to accept.
--
-- The index is a single JSON document living in-tree at registry/index.json
-- and served from the repo's default branch. Package binaries are release
-- assets, so the index stays small and reviewable in a diff.
--
-- Trust comes from the index and only from the index:
--
--   trusted     the hash is listed and the entry is author-published
--   community   the hash is listed and the entry is third-party
--   unsigned    the hash is not listed, or there is no usable index
--
-- "unsigned" is the answer for every degraded case — no cache, no network, a
-- malformed document, a bad signature. None of those raise; a registry that is
-- simply absent must leave the rest of mudscript working, so every path here
-- ends in an empty index rather than an error.
--
-- The index signature covers `jq -c -S '{formatVersion, generated, entries}'`
-- signed with the same RSA-2048 key Guardian checks MANIFEST.json against. An
-- index whose signature does not verify is discarded whole rather than served
-- with its trust stripped: a forged document should not get to choose which of
-- its own claims we believe.
return function(ms)

    local _home    = os.getenv("HOME")
    local _dataDir = _home .. "/.hammerspoon/data"

    local INDEX_URL     = "https://raw.githubusercontent.com/mudbourn/ms-utils/main/registry/index.json"
    local CACHE_PATH    = _dataDir .. "/ms_registry_cache.json"
    local BUNDLED_PATH  = _dataDir .. "/registry_index.json"
    local FORMAT_VERSION = 1
    local CACHE_TTL      = 6 * 60 * 60   -- seconds before refresh() refetches

    -- RSA-2048 public key for index signature verification.
    -- Must match _publicKey in MsGuardian.spoon and ms._updatePublicKey.
    local PUBLIC_KEY = [[
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA3pyxWISHUScKsmK0fyqA
QWUU0nzYEVpRYD+kRkZsL5AGqpjfNqfOky5bacE1jPXgu9LGz+b1pq1tuyZotvK/
FrMeQDCmGWiu5RXAqsyg0iN1c1CHSvWAT40xi6g54u9ot9LMfzmBETlwWd4QoXOA
OnT3KW0aia1EoyUjjNIRk6iv6pxi+BjHnGKoID6pAl9de+WASt/DETgCuKhQ7o/Y
iGn43A9ZutKUfkV+Muu1RcTy62zbXcQrzK3cyLl0M7gfTm0YWPzaf+d3ATNnq/9j
/952QfmXjVSGhU3EBxlEM6NWstNSNuaTWSMCcbcH+va/AMOHK1rRKQ3IOdzjYcQm
YQIDAQAB
-----END PUBLIC KEY-----
]]

    ms.registry = {}

    -- Live state. `_index` is always a table of the empty shape below, never
    -- nil, so every reader can index it without a guard.
    local function emptyIndex()
        return { formatVersion = FORMAT_VERSION, generated = nil, entries = {} }
    end

    local _index     = emptyIndex()
    local _byId      = {}
    local _byHash    = {}
    local _signed    = false      -- index verified against PUBLIC_KEY
    local _fetchedAt = nil        -- os.time() of the bytes currently loaded
    local _source    = "none"     -- "network" | "cache" | "bundled" | "none"
    local _error     = nil
    local _loading   = false

    -- Helpers --
        local function sq(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

        local function readFile(path)
            local f = io.open(path, "r")
            if not f then return nil end
            local body = f:read("*all"); f:close()
            return body
        end

        local function writeFile(path, body)
            hs.execute("mkdir -p " .. sq(_dataDir))
            local f = io.open(path, "w")
            if not f then return false end
            f:write(body); f:close()
            return true
        end

        local function tmpPath(tag)
            local base = os.getenv("TMPDIR") or "/tmp/"
            if not base:find("/$") then base = base .. "/" end
            return base .. "msreg-" .. tag .. "-" .. tostring(math.random(100000, 999999))
        end

        local function isHash(s)
            return type(s) == "string" and #s == 64 and s:match("^%x+$") ~= nil
        end

        -- Only http(s), and only hosts we publish from. An index entry is data,
        -- not instruction: it does not get to point the downloader anywhere.
        local ALLOWED_HOSTS = {
            ["github.com"]                = true,
            ["objects.githubusercontent.com"] = true,
            ["raw.githubusercontent.com"] = true,
            ["api.github.com"]            = true,
        }

        local function urlAllowed(url)
            if type(url) ~= "string" then return false end
            local host = url:match("^https://([^/]+)/")
            if not host then return false end
            host = host:gsub(":%d+$", ""):lower()
            return ALLOWED_HOSTS[host] == true
        end
    -- END Helpers --

    -- Signature --
        -- Mirrors Guardian's per-file manifest check: CI signs the minified,
        -- key-sorted JSON of the payload directly, so we rebuild exactly that
        -- byte sequence with `jq -c -S` before verifying. hs.json.encode alone
        -- will not do — it does not sort keys.
        local function verifySignature(doc)
            if type(doc) ~= "table" then return false end
            if type(doc.signature) ~= "string" or doc.signature == "" then
                return false
            end

            local payload = {
                formatVersion = doc.formatVersion,
                generated     = doc.generated,
                entries       = doc.entries,
            }
            local okEncode, unsorted = pcall(hs.json.encode, payload)
            if not okEncode or not unsorted then return false end

            local sortSrc = tmpPath("sort")
            if not writeFile(sortSrc, unsorted) then return false end
            local sortedOut = hs.execute("jq -c -S '.' " .. sq(sortSrc) .. " 2>/dev/null")
            os.remove(sortSrc)

            local minified = sortedOut
            if minified and minified:sub(-1) == "\n" then minified = minified:sub(1, -2) end
            if not minified or minified == "" then return false end

            local keyPath = tmpPath("pub")
            local sigPath = tmpPath("sig")
            local msgPath = tmpPath("msg")

            writeFile(keyPath, PUBLIC_KEY)
            writeFile(sigPath .. ".b64", doc.signature)
            hs.execute("base64 -D -i " .. sq(sigPath .. ".b64") .. " -o " .. sq(sigPath))
            os.remove(sigPath .. ".b64")
            writeFile(msgPath, minified)

            local out, ok = hs.execute(
                "openssl dgst -sha256 -verify " .. sq(keyPath) ..
                " -signature " .. sq(sigPath) ..
                " " .. sq(msgPath) .. " 2>&1"
            )

            os.remove(keyPath)
            os.remove(sigPath)
            os.remove(msgPath)

            return (ok and out and out:find("Verified OK") ~= nil) or false
        end
    -- END Signature --

    -- Parse --
        -- A bad row rejects the whole document, same as a bad signature. The
        -- alternative — skipping it — fails invisibly: the package simply is
        -- not in the library and nobody can tell whether that was intended.
        -- Rows only ever land here through a signed, reviewed commit, so a
        -- malformed one is a publishing mistake worth failing loudly on.
        --
        -- Returns nil plus a reason naming the offending row.
        local function normalise(raw, i)
            local function bad(why)
                return nil, "entry #" .. tostring(i) .. " (" ..
                    (type(raw) == "table" and tostring(raw.id) or "?") .. "): " .. why
            end
            if type(raw) ~= "table" then return bad("not an object") end
            if type(raw.id) ~= "string" or raw.id == "" then return bad("missing id") end
            if not isHash(raw.sha256) then return bad("sha256 is not 64 hex characters") end
            if not ms.package.spec(raw.type) then return bad("unknown type " .. tostring(raw.type)) end
            if raw.url ~= nil and not urlAllowed(raw.url) then return bad("download URL not permitted") end

            return {
                id          = raw.id,
                type        = raw.type,
                name        = type(raw.name) == "string" and raw.name or raw.id,
                version     = type(raw.version) == "string" and raw.version or "",
                author      = type(raw.author) == "string" and raw.author or "",
                description = type(raw.description) == "string" and raw.description or "",
                website     = type(raw.website) == "string" and raw.website or "",
                sha256      = raw.sha256:lower(),
                url         = raw.url,
                size        = tonumber(raw.size) or nil,
                requires    = type(raw.requires) == "string" and raw.requires or nil,
                -- Anything not explicitly marked author-published is community.
                trust       = raw.trust == "trusted" and "trusted" or "community",
            }
        end

        -- Installs `doc` as the live index. Returns false (leaving the previous
        -- index in place) if the document is not a usable, signed index.
        local function adopt(doc, source, requireSignature)
            if type(doc) ~= "table" or type(doc.entries) ~= "table" then
                return false, "Malformed index."
            end
            if doc.formatVersion and tonumber(doc.formatVersion) ~= FORMAT_VERSION then
                return false, "Unsupported index format: " .. tostring(doc.formatVersion)
            end

            local signed = verifySignature(doc)
            if requireSignature and not signed then
                return false, "Index signature did not verify."
            end

            local entries, byId, byHash = {}, {}, {}
            for i, raw in ipairs(doc.entries) do
                local e, why = normalise(raw, i)
                if not e then return false, why end
                -- A duplicate is ambiguous about which row's trust applies, so
                -- it is rejected rather than resolved by ordering.
                if byId[e.id] then
                    return false, "entry #" .. i .. ": duplicate id " .. e.id
                end
                if byHash[e.sha256] then
                    return false, "entry #" .. i .. ": duplicate sha256 for " .. e.id
                end
                entries[#entries + 1] = e
                byId[e.id]            = e
                byHash[e.sha256]      = e
            end

            _index     = { formatVersion = FORMAT_VERSION, generated = doc.generated, entries = entries }
            _byId      = byId
            _byHash    = byHash
            _signed    = signed
            _source    = source
            _fetchedAt = tonumber(doc._fetchedAt) or os.time()
            return true
        end

        local function decode(body)
            if type(body) ~= "string" or body == "" then return nil end
            local ok, doc = pcall(hs.json.decode, body)
            if not ok or type(doc) ~= "table" then return nil end
            return doc
        end
    -- END Parse --

    -- Load --
        -- Cache first, then the copy that shipped with the install. Both are
        -- signature-checked; neither failing is an error worth surfacing,
        -- because the next refresh() is the real answer.
        local function loadLocal()
            local cached = decode(readFile(CACHE_PATH))
            if cached and adopt(cached, "cache", true) then return true end

            local bundled = decode(readFile(BUNDLED_PATH))
            if bundled and adopt(bundled, "bundled", true) then return true end

            return false
        end

        local function persist(doc)
            doc._fetchedAt = os.time()
            local ok, body = pcall(hs.json.encode, doc)
            if ok and body then writeFile(CACHE_PATH, body) end
        end
    -- END Load --

    -- Public: refresh --
        -- opts = { force = bool }   force refetches inside the TTL.
        -- cb(ok, err) always fires exactly once.
        ms.registry.refresh = function(opts, cb)
            if type(opts) == "function" then opts, cb = {}, opts end
            opts = opts or {}
            local done = function(ok, err)
                _loading = false
                if type(cb) == "function" then pcall(cb, ok, err) end
            end

            if _loading then
                if type(cb) == "function" then pcall(cb, false, "Refresh already in progress.") end
                return
            end

            if not opts.force and _fetchedAt and (os.time() - _fetchedAt) < CACHE_TTL then
                if type(cb) == "function" then pcall(cb, true, nil) end
                return
            end

            _loading = true
            hs.http.asyncGet(INDEX_URL, nil, function(code, body, _)
                if code ~= 200 then
                    -- Network failure is not fatal: whatever we already had,
                    -- cached or bundled, stays serving.
                    _error = "Could not reach the registry (HTTP " .. tostring(code) .. ")."
                    if #_index.entries == 0 then loadLocal() end
                    return done(false, _error)
                end

                local doc = decode(body)
                if not doc then
                    _error = "Registry index was not readable JSON."
                    return done(false, _error)
                end

                local ok, err = adopt(doc, "network", true)
                if not ok then
                    _error = err
                    return done(false, err)
                end

                _error = nil
                persist(doc)
                done(true, nil)
            end)
        end
    -- END refresh --

    -- Public: read --
        -- opts = { type = "theme", query = "substring" }
        ms.registry.list = function(opts)
            opts = opts or {}
            local q = type(opts.query) == "string" and opts.query:lower() or nil
            local out = {}
            for _, e in ipairs(_index.entries) do
                local keep = true
                if opts.type and e.type ~= opts.type then keep = false end
                if keep and q and q ~= "" then
                    keep = (e.name:lower():find(q, 1, true) ~= nil)
                        or (e.author:lower():find(q, 1, true) ~= nil)
                        or (e.description:lower():find(q, 1, true) ~= nil)
                end
                if keep then out[#out + 1] = e end
            end
            return out
        end

        ms.registry.get  = function(id)   return type(id)   == "string" and _byId[id] or nil end

        ms.registry.find = function(hash)
            if not isHash(hash) then return nil end
            return _byHash[hash:lower()]
        end

        -- The seam ms.package.verify already takes. Signature is fixed:
        -- (hash, manifest) -> "trusted" | "community" | "unsigned".
        --
        -- An unsigned index can never elevate anything, and a hash nobody
        -- listed is "unsigned" — never an error, never a nil.
        ms.registry.trustLookup = function(hash, manifest)
            if not _signed then return "unsigned" end
            local entry = ms.registry.find(hash)
            if not entry then return "unsigned" end

            -- The index vouches for a hash under a declared type. A package
            -- claiming to be something else is not the thing that was listed.
            if type(manifest) == "table" and manifest.type and manifest.type ~= entry.type then
                return "unsigned"
            end

            return entry.trust
        end

        -- Everything D's tab needs to render a state, in one call.
        ms.registry.status = function()
            return {
                state     = _loading and "loading" or (#_index.entries > 0 and "ready" or "empty"),
                count     = #_index.entries,
                signed    = _signed,
                source    = _source,
                generated = _index.generated,
                fetchedAt = _fetchedAt,
                error     = _error,
            }
        end
    -- END read --

    -- Public: download --
        -- Fetches an entry's binary to a temp path and verifies its hash
        -- against the index before handing the path back. It does not install:
        -- the caller passes the path to ms.package.install, which re-verifies
        -- with trustLookup on its own terms.
        --
        -- cb(path, err) — exactly one of the two is non-nil.
        ms.registry.download = function(idOrEntry, cb)
            local done = function(path, err)
                if type(cb) == "function" then pcall(cb, path, err) end
            end

            local entry = type(idOrEntry) == "table" and idOrEntry or ms.registry.get(idOrEntry)
            if not entry then return done(nil, "No such package in the registry.") end
            if not urlAllowed(entry.url) then
                return done(nil, "Package download location is not permitted.")
            end

            hs.http.asyncGet(entry.url, nil, function(code, body, _)
                if code ~= 200 or not body or body == "" then
                    return done(nil, "Download failed (HTTP " .. tostring(code) .. ").")
                end

                local path = tmpPath("dl") .. ".mspkg"
                local f = io.open(path, "wb")
                if not f then return done(nil, "Could not write the download.") end
                f:write(body); f:close()

                local out = hs.execute("shasum -a 256 " .. sq(path) .. " 2>/dev/null")
                local got = (out and #out >= 64) and out:sub(1, 64):lower() or nil
                if got ~= entry.sha256 then
                    os.remove(path)
                    return done(nil, "Downloaded package did not match the registry hash.")
                end

                done(path, nil)
            end)
        end
    -- END download --

    -- Boot --
        -- Load whatever is on disk now so trustLookup answers immediately;
        -- the network refresh is best-effort and silent.
        loadLocal()
    -- END Boot --

end
