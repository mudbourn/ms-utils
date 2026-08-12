-- ms_package — Typed Package Format (.mspkg) --
--
-- A .mspkg is a zip archive carrying a single kind of shareable content plus a
-- manifest (`mspkg.json`) describing what it is and what it contains.
--
-- Five types exist. Each declares exactly which paths it may carry, so a theme
-- package can never smuggle macro code and a sound package can never overwrite
-- settings:
--
--   macro    ms_macros.lua and/or ms_macros_visual.json, plus sounds/macro/
--   theme    ms_theme.json, plus ui/fonts/
--   sound    sounds/active/ and sounds/macro/, plus the slot assignment map
--   plugin   a Spoon under Spoons/<Name>.spoon/ — the third-party surface
--   profile  the whole set — macros, settings, theme and sounds together
--
-- `profile` is the legacy monolithic shape: an archive with no manifest is read
-- as a formatVersion-0 profile so packages made before typing still import.
--
-- Macro packages carry Lua, JSON, or both. Neither is legacy — hand-written
-- ms_macros.lua and builder-authored ms_macros_visual.json are permanent peers,
-- and `macroFormat` records which of them a package actually ships.
return function(ms)

    local _home     = os.getenv("HOME")
    local _hsDir    = _home .. "/.hammerspoon"
    local _dataDir  = _hsDir .. "/data"

    local MANIFEST_NAME  = "mspkg.json"
    local FORMAT_VERSION = 1

    ms.package = {}

    -- Helpers --
        local function sq(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

        local function hashFile(path)
            local out = hs.execute("shasum -a 256 " .. sq(path) .. " 2>/dev/null")
            return (out and #out >= 64) and out:sub(1, 64):lower() or nil
        end

        local function fileExists(path)
            local a = hs.fs.attributes(path)
            return a ~= nil and a.mode == "file"
        end

        local function readFile(path)
            local f = io.open(path, "r")
            if not f then return nil end
            local body = f:read("*all"); f:close()
            return body
        end

        local function writeFile(path, body)
            local f = io.open(path, "w")
            if not f then return false end
            f:write(body); f:close()
            return true
        end

        -- Reject anything that could escape the extraction root.
        local function safeRelPath(p)
            if type(p) ~= "string" or p == "" then return nil end
            if p:find("^/") or p:find("^~") then return nil end
            if p:find("%.%.") then return nil end
            if p:find("^%.") then return nil end
            return p
        end

        local function tempDir(tag)
            local base = os.getenv("TMPDIR") or "/tmp/"
            if not base:find("/$") then base = base .. "/" end
            local dir = base .. "mspkg-" .. tag .. "-" .. tostring(math.random(100000, 999999))
            hs.execute("mkdir -p " .. sq(dir))
            return dir
        end

        -- Component-wise, not lexicographic: "1.10.0" < "1.9.0" is true as a
        -- string compare, which read every double-digit version as older than
        -- its single-digit predecessor. Unparseable input compares as equal so
        -- a malformed `requires` warns about nothing rather than everything.
        local function versionLess(a, b)
            local am = { tostring(a):match("^(%d+)%.(%d+)%.(%d+)$") }
            local bm = { tostring(b):match("^(%d+)%.(%d+)%.(%d+)$") }
            if #am < 3 or #bm < 3 then return false end
            for i = 1, 3 do
                local x, y = tonumber(am[i]), tonumber(bm[i])
                if x ~= y then return x < y end
            end
            return false
        end

        local function rmrf(dir)
            if dir and dir:find("mspkg%-") then hs.execute("/bin/rm -rf " .. sq(dir)) end
        end
    -- END Helpers --

    -- Type Specs --
        -- `paths` are the path prefixes a type may carry. `required` must be
        -- satisfied by at least one present file or the package is malformed.
        local TYPE_SPECS = {
            macro = {
                label    = "Macro Pack",
                paths    = { "ms_macros.lua", "ms_macros_visual.json", "sounds/macro/" },
                required = { "ms_macros.lua", "ms_macros_visual.json" },
            },
            -- Sounds are a theme aspect, not a profile one: a theme is the
            -- whole sensory surface, so it may carry audio and the slot map
            -- that gives that audio meaning. Whether an export actually
            -- includes them is the user's call (bundleSoundsWithTheme) —
            -- these are the paths a theme is *allowed* to carry, not a list
            -- of what it must.
            theme = {
                label    = "Theme",
                -- No sounds/defaults/: those ship with the app, are identical
                -- everywhere, and cannot be removed — carrying them would put
                -- the same bytes in every theme anyone exports.
                paths    = {
                    "ms_theme.json", "ui/fonts/",
                    "sounds/active/", "sounds/macro/",
                    "sound_assign.json",
                },
                required = { "ms_theme.json" },
            },
            -- Same rule as the theme above, and for the same reason: a sound
            -- pack carries the audio a user can actually change. It used to
            -- name sounds/Default/, which is not a directory that exists —
            -- the library is sounds/defaults/ — so the required check could
            -- never pass and no sound pack could be built or installed. It is
            -- gone rather than corrected: letting a package write into
            -- sounds/defaults/ is letting it overwrite the fallback floor
            -- every slot lands on.
            sound = {
                label    = "Sound Pack",
                paths    = { "sounds/active/", "sounds/macro/", "sound_assign.json" },
                required = { "sounds/active/" },
            },
            -- Spoons/ is the third-party surface: lib/ is first-party only, so
            -- a plugin can no longer land beside core modules. Everything is
            -- nested under Spoons/<Name>.spoon/ rather than sitting at the
            -- install root — a flat plugin.json would mean the second plugin
            -- installed overwrites the first one's manifest.
            plugin = {
                label    = "Plugin",
                paths    = { "Spoons/" },
                required = { "Spoons/" },
            },
            -- A profile is monolithic: the whole look and feel in one archive,
            -- so it carries its audio and fonts alongside the config. The
            -- theme/sound overlap the earlier design avoided is not a conflict
            -- here — a profile is a wholesale swap, not a layer, so on install
            -- it simply is the source of truth for every file it names.
            -- sounds/defaults/ is still excluded: it ships identical with every
            -- install and must never be overwritten by a package.
            profile = {
                label    = "Profile",
                paths    = {
                    "ms_macros.lua", "ms_macros_visual.json", "ms_settings.json",
                    "ms_settings_default.json", "ms_theme.json",
                    "sounds/active/", "sounds/macro/", "ui/fonts/", "sound_assign.json",
                },
                required = {},
            },
        }

        ms.package.TYPES = { "macro", "theme", "sound", "plugin", "profile" }

        ms.package.spec = function(kind) return TYPE_SPECS[kind] end

        -- A verify report's declared type, or nil. A legacy archive has no
        -- declared type and can never be a plugin, so it reads as nil here.
        local function manifestType(report)
            local m = type(report) == "table" and report.manifest
            if type(m) ~= "table" or m.legacy then return nil end
            return m.type
        end

        -- The single seam the "disable security protections" control wires
        -- into. Defaults closed: with nothing wired up, no unvalidated plugin
        -- can install. Anything replacing this must be sticky and visible —
        -- a per-import prompt is exactly what this exists to prevent.
        ms.package.protectionDisabled = function() return false end

        -- Guardian's plugin ledger. Guardian reads this before ms exists, so
        -- the two sides share only a file format and a hash recipe — keep
        -- _hashSpoonTree in ms_guardian.lua byte-identical to spoonTreeHash
        -- here or every install will read as tampered on the next boot.
        local _ledgerPath = _dataDir .. "/.ms_plugin_ledger.json"

        local function spoonTreeHash(absDir)
            local out, ok = hs.execute(
                "cd " .. sq(absDir) .. " && find . -type f ! -name '.DS_Store' " ..
                "-exec shasum -a 256 {} + 2>/dev/null | sort -k2 | shasum -a 256"
            )
            if not ok or not out then return nil end
            return out:match("^(%x+)")
        end

        local function readLedger()
            local raw = readFile(_ledgerPath)
            if not raw then return nil end
            local ok, tbl = pcall(hs.json.decode, raw)
            if ok and type(tbl) == "table" and type(tbl.plugins) == "table" then
                return tbl
            end
            return nil
        end

        local function writeLedger(ledger)
            local ok, json = pcall(hs.json.encode, ledger)
            if not ok then return false end
            return writeFile(_ledgerPath, json .. "\n")
        end

        ms.package.recordPlugins = function(names, manifest)
            local ledger = readLedger() or { version = 1, plugins = {} }

            for name in pairs(names) do
                local hash = spoonTreeHash(_hsDir .. "/Spoons/" .. name)
                if hash then
                    -- The display fields are recorded here because this is the
                    -- only moment they exist: install copies the Spoons/ tree
                    -- verbatim, so nothing on disk afterwards remembers what
                    -- the package called itself. The alternative — reading a
                    -- name out of the Spoon's own init.lua — means parsing
                    -- third-party code to draw a list, which is not a trade
                    -- worth making for a subtitle.
                    ledger.plugins[name] = {
                        hash        = hash,
                        id          = manifest and manifest.id or nil,
                        name        = manifest and manifest.name or nil,
                        version     = manifest and manifest.version or nil,
                        author      = manifest and manifest.author or nil,
                        website     = manifest and manifest.website or nil,
                        description = manifest and manifest.description or nil,
                        installedAt = os.date("!%Y-%m-%dT%H:%M:%SZ"),
                    }
                end
            end

            return writeLedger(ledger)
        end

        -- True when `rel` sits under one of the type's allowed prefixes.
        local function pathAllowed(kind, rel)
            local spec = TYPE_SPECS[kind]
            if not spec then return false end
            for _, prefix in ipairs(spec.paths) do
                if prefix:find("/$") then
                    if rel:sub(1, #prefix) == prefix then return true end
                elseif rel == prefix then
                    return true
                end
            end
            return false
        end

        -- At least one of the type's required paths must be present. `rels` is
        -- a flat list of archive-relative paths. Enforced on both sides: pack
        -- refuses to build one, verify refuses to trust one built elsewhere.
        local function requiredSatisfied(kind, rels)
            local spec = TYPE_SPECS[kind]
            if not spec then return false end
            if #spec.required == 0 then return true end
            for _, req in ipairs(spec.required) do
                for _, rel in ipairs(rels) do
                    if rel == req or (req:find("/$") and rel:sub(1, #req) == req) then
                        return true
                    end
                end
            end
            return false
        end

        ms.package.pathAllowed = pathAllowed
        ms.package.requiredSatisfied = requiredSatisfied
    -- END Type Specs --

    -- Fingerprint --
        -- Recorded at pack time and compared at import time so a package built
        -- elsewhere warns instead of failing obscurely.
        ms.package.fingerprint = function()
            local arch = hs.execute("/usr/bin/uname -m 2>/dev/null") or ""
            return {
                os        = "macos",
                arch      = arch:gsub("%s+", ""),
                mudscript = ms.version or "unknown",
            }
        end

        -- Display name for the OS a package was built on. Falls back to the
        -- raw value rather than "unknown" so a package from a platform this
        -- build has never heard of still reads as something specific.
        local OS_LABELS = { macos = "macOS", windows = "Windows" }

        ms.package.osLabel = function(manifest)
            local os_ = type(manifest) == "table" and (manifest.platform or {}).os
            if type(os_) ~= "string" or os_ == "" then return "an unknown platform" end
            return OS_LABELS[os_] or os_
        end

        -- Returns a list of human-readable warnings; empty means clean.
        ms.package.compatWarnings = function(manifest)
            local warnings = {}
            if type(manifest) ~= "table" then return warnings end

            local fp   = manifest.platform or {}
            local here = ms.package.fingerprint()

            if fp.os and fp.os ~= "" and fp.os ~= here.os then
                warnings[#warnings + 1] =
                    "Built on " .. ms.package.osLabel(manifest) .. ", importing on " ..
                    (OS_LABELS[here.os] or here.os) ..
                    ". Key names, modifiers and camera behaviour differ between platforms."
                if manifest.type == "macro" and manifest.macroFormat == "lua" then
                    warnings[#warnings + 1] =
                        "This pack ships hand-written Lua only. Cross-platform packs travel " ..
                        "best as ms_macros_visual.json, which is compiled on import."
                end
            end

            if fp.arch and fp.arch ~= "" and here.arch ~= "" and fp.arch ~= here.arch then
                warnings[#warnings + 1] =
                    "Built for " .. tostring(fp.arch) .. ", this machine is " .. here.arch ..
                    ". Only matters for plugins shipping native code."
            end

            -- Two shapes in the wild: the manifest nests it under `mudscript`,
            -- the registry index carries it as a bare string. Accept both.
            local rq  = manifest.requires
            local req = (type(rq) == "table" and rq.mudscript)
                     or (type(rq) == "string" and rq)
                     or nil
            if type(req) == "string" and req ~= "" then
                local want = req:match("(%d+%.%d+%.%d+)")
                local have = tostring(ms.version or ""):match("(%d+%.%d+%.%d+)")
                if want and have and versionLess(have, want) then
                    warnings[#warnings + 1] =
                        "Needs mudscript " .. req .. "; this install is " .. tostring(ms.version) .. "."
                end
            end

            return warnings
        end
    -- END Fingerprint --

    -- Inspect --
        -- Reads the manifest without extracting the archive. An archive with no
        -- manifest is reported as a formatVersion-0 profile (pre-typing export).
        ms.package.inspect = function(path)
            if not fileExists(path) then return nil, "Package not found." end

            local raw = hs.execute("/usr/bin/unzip -p " .. sq(path) .. " " .. MANIFEST_NAME .. " 2>/dev/null")

            if raw and raw ~= "" then
                local ok, decoded = pcall(hs.json.decode, raw)
                if ok and type(decoded) == "table" and decoded.type then
                    if not TYPE_SPECS[decoded.type] then
                        return nil, "Unknown package type: " .. tostring(decoded.type)
                    end
                    return decoded
                end
            end

            -- Legacy: untyped archive. Only call it a profile if it looks like one.
            local listing = hs.execute("/usr/bin/unzip -Z1 " .. sq(path) .. " 2>/dev/null") or ""
            if listing:find("ms_macros%.lua") or listing:find("ms_settings%.json") then
                return {
                    formatVersion = 0,
                    type          = "profile",
                    name          = path:match("([^/]+)%.mspkg$") or "Untitled Profile",
                    legacy        = true,
                }
            end

            return nil, "Not a recognisable mudscript package."
        end

        -- Flat list of archive members, directories dropped.
        ms.package.contents = function(path)
            local listing = hs.execute("/usr/bin/unzip -Z1 " .. sq(path) .. " 2>/dev/null") or ""
            local out = {}
            for line in listing:gmatch("[^\r\n]+") do
                if not line:find("/$") and line ~= MANIFEST_NAME and not line:find("^__MACOSX/") then
                    out[#out + 1] = line
                end
            end
            return out
        end
    -- END Inspect --

    -- Verify --
        -- Integrity is self-contained: every file the manifest lists must be
        -- present and hash as recorded. Trust is external — `trustLookup` is
        -- supplied by ms_registry and maps a package hash to a trust level.
        --
        -- Returns { ok, trust, hash, issues = {...}, warnings = {...} }
        -- trust is one of: "trusted" | "community" | "unsigned" | "tampered"
        ms.package.verify = function(path, trustLookup)
            local result = { ok = false, trust = "unsigned", issues = {}, warnings = {} }

            local manifest, err = ms.package.inspect(path)
            if not manifest then
                result.issues[#result.issues + 1] = err or "Unreadable package."
                return result
            end
            result.manifest = manifest

            result.hash = hashFile(path)
            if not result.hash then
                result.issues[#result.issues + 1] = "Could not hash package."
                return result
            end

            -- Every member must be legal for the declared type.
            local members = ms.package.contents(path)
            for _, rel in ipairs(members) do
                if not safeRelPath(rel) then
                    result.issues[#result.issues + 1] = "Unsafe path in package: " .. rel
                elseif not manifest.legacy and not pathAllowed(manifest.type, rel) then
                    result.issues[#result.issues + 1] =
                        "File not permitted in a " .. manifest.type .. " package: " .. rel
                end
            end

            -- ...and the type's own minimum must be met. pack enforces this on
            -- the way out, but a package built by anything other than this
            -- packer has never been through that gate, which is exactly the
            -- case the registry exists to handle.
            if not manifest.legacy and not requiredSatisfied(manifest.type, members) then
                local spec = TYPE_SPECS[manifest.type]
                result.issues[#result.issues + 1] =
                    "A " .. tostring(manifest.type) .. " package needs " ..
                    table.concat(spec and spec.required or {}, " or ") .. "."
            end

            -- Recorded hashes must match the archive's actual bytes.
            if type(manifest.contents) == "table" then
                local dir = tempDir("verify")
                hs.execute("/usr/bin/unzip -qq -o " .. sq(path) .. " -d " .. sq(dir) .. " 2>/dev/null")
                for rel, want in pairs(manifest.contents) do
                    local got = hashFile(dir .. "/" .. rel)
                    if not got then
                        result.issues[#result.issues + 1] = "Listed but missing: " .. rel
                    elseif got ~= tostring(want):lower() then
                        result.issues[#result.issues + 1] = "Modified since packing: " .. rel
                    end
                end
                rmrf(dir)
            end

            if #result.issues > 0 then
                result.trust = "tampered"
                return result
            end

            if type(trustLookup) == "function" then
                local ok, level = pcall(trustLookup, result.hash, manifest)
                if ok and type(level) == "string" then result.trust = level end
            end

            result.warnings = ms.package.compatWarnings(manifest)
            result.ok = true
            return result
        end
    -- END Verify --

    -- Profile components --
        -- A profile is a composition, and these rules are the single source of
        -- truth for how it decomposes — used both to record the `components`
        -- block at pack time and to cut a profile apart in split().
        --
        -- Sounds have a canonical, exclusive home in the `sound` package. The
        -- `theme` may ALSO carry a copy when includeSoundsInTheme is set — the
        -- same opt-in the standalone theme export offers — so "just the theme"
        -- and "just the sounds" stay separately downloadable by default.
        -- Macro-triggered audio (sounds/macro/) travels with the macros so a
        -- macro pack is self-contained. Settings are profile-only: no
        -- shareable sub-type, never emitted as a component package.
        local PROFILE_COMPONENT_KINDS = { "theme", "sound", "macro" }

        local function isAudioRel(rel)
            return rel:sub(1, 14) == "sounds/active/"
                or rel:sub(1, 13) == "sounds/macro/"
                or rel == "sound_assign.json"
        end

        -- Returns { theme = {files={...}, includesSounds=bool}, sound = {files},
        -- macro = {files}, settings = {files} }. Membership can overlap (audio
        -- is in `sound` always and `theme` optionally) — each component is its
        -- own package, so that is fine.
        local function profileComponents(relPaths, includeSoundsInTheme)
            local comp = {
                theme    = { files = {}, includesSounds = includeSoundsInTheme and true or false },
                sound    = { files = {} },
                macro    = { files = {} },
                settings = { files = {} },
            }
            local function add(t, r) t[#t + 1] = r end
            for _, r in ipairs(relPaths) do
                if r == "ms_theme.json" or r:sub(1, 9) == "ui/fonts/" then add(comp.theme.files, r) end
                if includeSoundsInTheme and isAudioRel(r) then add(comp.theme.files, r) end
                if isAudioRel(r) then add(comp.sound.files, r) end
                if r == "ms_macros.lua" or r == "ms_macros_visual.json"
                    or r:sub(1, 13) == "sounds/macro/" then add(comp.macro.files, r) end
                if r == "ms_settings.json" or r == "ms_settings_default.json" then
                    add(comp.settings.files, r)
                end
            end
            return comp
        end
    -- END Profile components --

    -- Pack --
        -- opts = {
        --   type, name, version, author, website, description,
        --   files   = { ["ms_theme.json"] = "/abs/source/path", ... },
        --   out     = "/abs/dest.mspkg",
        -- }
        ms.package.pack = function(opts)
            opts = opts or {}
            local kind = opts.type
            local spec = TYPE_SPECS[kind]
            if not spec then return nil, "Unknown package type." end
            if type(opts.files) ~= "table" or next(opts.files) == nil then
                return nil, "Nothing to pack."
            end
            if not opts.out or opts.out == "" then return nil, "No output path." end

            local staging = tempDir("pack")
            local manifest = {
                formatVersion = FORMAT_VERSION,
                type          = kind,
                name          = opts.name or "Untitled",
                version       = opts.version or "1.0.0",
                author        = opts.author,
                website       = opts.website,
                description   = opts.description,
                created       = os.date("!%Y-%m-%dT%H:%M:%SZ"),
                platform      = ms.package.fingerprint(),
                requires      = opts.requires,
                contents      = {},
            }

            local staged = 0
            for rel, src in pairs(opts.files) do
                local clean = safeRelPath(rel)
                if not clean then
                    rmrf(staging); return nil, "Unsafe path: " .. tostring(rel)
                end
                if not pathAllowed(kind, clean) then
                    rmrf(staging)
                    return nil, "A " .. kind .. " package cannot carry " .. clean .. "."
                end
                if fileExists(src) then
                    local destDir = (staging .. "/" .. clean):match("(.*)/")
                    if destDir then hs.execute("mkdir -p " .. sq(destDir)) end
                    local _, ok = hs.execute("/bin/cp " .. sq(src) .. " " .. sq(staging .. "/" .. clean))
                    if ok then
                        manifest.contents[clean] = hashFile(staging .. "/" .. clean)
                        staged = staged + 1
                    end
                end
            end

            if staged == 0 then rmrf(staging); return nil, "No readable source files." end

            local packed = {}
            for rel in pairs(manifest.contents) do packed[#packed + 1] = rel end
            if not requiredSatisfied(kind, packed) then
                rmrf(staging)
                return nil, "A " .. kind .. " package needs " ..
                    table.concat(spec.required, " or ") .. "."
            end

            if kind == "macro" then
                local hasLua  = manifest.contents["ms_macros.lua"] ~= nil
                local hasJSON = manifest.contents["ms_macros_visual.json"] ~= nil
                manifest.macroFormat = (hasLua and hasJSON) and "both"
                    or (hasJSON and "json" or "lua")
            end

            -- Record the composition so the profile is self-describing: split
            -- and (later) partial install read this map instead of re-deriving.
            -- Only components actually present are listed. includeSoundsInTheme
            -- defaults false — a clean split keeps theme (visuals) and sound
            -- (audio) separate unless the author opts the audio into the theme.
            if kind == "profile" then
                local rels = {}
                for rel in pairs(manifest.contents) do rels[#rels + 1] = rel end
                local includeSounds = opts.includeSoundsInTheme
                if includeSounds == nil then includeSounds = false end
                local comp = profileComponents(rels, includeSounds)
                manifest.components = {}
                for _, k in ipairs(PROFILE_COMPONENT_KINDS) do
                    if #comp[k].files > 0 then manifest.components[k] = comp[k] end
                end
                if #comp.settings.files > 0 then manifest.components.settings = comp.settings end
            end

            if not writeFile(staging .. "/" .. MANIFEST_NAME, hs.json.encode(manifest)) then
                rmrf(staging); return nil, "Could not write manifest."
            end

            hs.execute("/bin/rm -f " .. sq(opts.out))
            local outDir = opts.out:match("(.*)/")
            if outDir then hs.execute("mkdir -p " .. sq(outDir)) end

            local _, zipped = hs.execute(
                "cd " .. sq(staging) .. " && /usr/bin/zip -qq -r -X " .. sq(opts.out) .. " . 2>/dev/null"
            )
            rmrf(staging)

            if not zipped or not fileExists(opts.out) then return nil, "Could not write package." end

            manifest.hash = hashFile(opts.out)
            return manifest
        end
    -- END Pack --

    -- Split --
        -- Take a profile apart into its component packages. Each output is a
        -- standalone typed .mspkg built by pack(), indistinguishable from one
        -- authored directly, so it publishes and installs like any other.
        --
        -- File lists are always re-derived from the archive's real contents
        -- (not trusted from a possibly-hand-edited manifest); the manifest's
        -- recorded includeSoundsInTheme is used only as the default toggle. A
        -- legacy profile with no components block therefore still splits.
        --
        -- opts = { includeSoundsInTheme = bool }  -- default: the profile's own
        --         recorded preference, else false.
        -- Returns { made = {{type,path,name}...}, skipped = {{type,why}...} }.
        ms.package.split = function(path, outDir, opts)
            opts = opts or {}
            local manifest, err = ms.package.inspect(path)
            if not manifest then return nil, err or "Unreadable package." end
            if manifest.type ~= "profile" then
                return nil, "Only a profile can be split (this is a " ..
                    tostring(manifest.type) .. " package)."
            end
            if not outDir or outDir == "" then return nil, "No output folder." end
            outDir = outDir:gsub("/$", "")

            local includeSounds = opts.includeSoundsInTheme
            if includeSounds == nil then
                local tc = type(manifest.components) == "table" and manifest.components.theme
                includeSounds = (type(tc) == "table" and tc.includesSounds) and true or false
            end

            local rels = ms.package.contents(path)
            local comp = profileComponents(rels, includeSounds)

            local staging = tempDir("split")
            hs.execute("/usr/bin/unzip -qq -o " .. sq(path) .. " -d " .. sq(staging) .. " 2>/dev/null")

            -- Base name for the outputs; drop a trailing "profile" so
            -- "Combat Warriors profile" yields "Combat Warriors-theme.mspkg".
            local base = manifest.name
                or (path:match("([^/]+)%.mspkg$")) or "Profile"
            base = base:gsub("%s+[Pp]rofile$", "")
            local fileBase = base:gsub("[/\\%c]", ""):gsub("%s+$", "")
            if fileBase == "" then fileBase = "Profile" end

            local made, skipped = {}, {}
            for _, kind in ipairs(PROFILE_COMPONENT_KINDS) do
                local files, present = {}, {}
                for _, rel in ipairs(comp[kind].files) do
                    local abs = staging .. "/" .. rel
                    if fileExists(abs) then files[rel] = abs; present[#present + 1] = rel end
                end
                if #present == 0 then
                    -- This component simply is not in the profile; omit quietly.
                elseif not requiredSatisfied(kind, present) then
                    skipped[#skipped + 1] = { type = kind, why = "missing " ..
                        table.concat((TYPE_SPECS[kind] or {}).required or {}, " or ") }
                else
                    local label = (TYPE_SPECS[kind] or {}).label or kind
                    local out = outDir .. "/" .. fileBase .. "-" .. kind .. ".mspkg"
                    local m, perr = ms.package.pack({
                        type    = kind,
                        name    = base .. " " .. label,
                        version = manifest.version,
                        author  = manifest.author,
                        website = manifest.website,
                        files   = files,
                        out     = out,
                    })
                    if m then made[#made + 1] = { type = kind, path = out, name = base .. " " .. label }
                    else skipped[#skipped + 1] = { type = kind, why = perr or "pack failed" } end
                end
            end
            rmrf(staging)
            return { made = made, skipped = skipped }
        end
    -- END Split --

    -- Install --
        -- Extracts a verified package into the live install. Every destination
        -- is derived from the type spec, never from the archive, so a package
        -- can only ever write where its own type is allowed to.
        --
        -- opts = { force = bool, trustLookup = fn, backup = bool (default true) }
        ms.package.install = function(path, opts)
            opts = opts or {}

            local report = ms.package.verify(path, opts.trustLookup)
            if not report.ok then
                return nil, table.concat(report.issues, "\n")
            end

            -- Plugins are inside the trust boundary and `force` does not reach
            -- them. Every other type is data the app interprets; a plugin is
            -- code that runs with the app's own privileges, so "import anyway"
            -- — one confirmation dialog — is far too cheap a bypass. The only
            -- way to run an unvalidated plugin is to turn protection off
            -- wholesale, which is a deliberate, visible, sticky act.
            if manifestType(report) == "plugin" and report.trust ~= "trusted" then
                if not ms.package.protectionDisabled() then
                    return nil,
                        "This plugin is not in the validated library.\n" ..
                        "Plugins run as code, so they cannot be imported one-off. " ..
                        "Disable security protections entirely to run unvalidated plugins."
                end
            elseif report.trust == "unsigned" and not opts.force then
                return nil, "Package is not in the validated library. Import anyway to continue."
            end

            -- ms_macros.lua is executable code. The hand-rolled profile
            -- importer, the compiler and the macros panel all scan it with
            -- ms.auditMacros before it can run; the generic install path did
            -- not, so a profile or macro package installed here — including one
            -- pulled from the registry via Browse — could land unscanned code
            -- on disk. Scan it before anything is written, and reject the whole
            -- install on failure, exactly as the importer does.
            if ms.auditMacros then
                for _, rel in ipairs(ms.package.contents(path)) do
                    if rel == "ms_macros.lua" then
                        local src = hs.execute("/usr/bin/unzip -p " .. sq(path) .. " ms_macros.lua 2>/dev/null")
                        if type(src) == "string" and src ~= "" then
                            local errs = ms.auditMacros(src)
                            if type(errs) == "table" and #errs > 0 then
                                return nil, "Macro security scan failed:\n  \xe2\x80\xa2 " ..
                                    table.concat(errs, "\n  \xe2\x80\xa2 ")
                            end
                        end
                        break
                    end
                end
            end

            local manifest = report.manifest
            local staging  = tempDir("install")
            hs.execute("/usr/bin/unzip -qq -o " .. sq(path) .. " -d " .. sq(staging) .. " 2>/dev/null")

            local installed, failed = {}, {}

            for _, rel in ipairs(ms.package.contents(path)) do
                local clean = safeRelPath(rel)
                if clean and (manifest.legacy or pathAllowed(manifest.type, clean)) then
                    -- data/ files live under data/; everything else mirrors the install root.
                    local dest
                    if clean:find("^ms_") and clean:find("%.json$") then
                        dest = _dataDir .. "/" .. clean
                    elseif clean == "ms_macros.lua" then
                        dest = _hsDir .. "/ms_macros.lua"
                    else
                        dest = _hsDir .. "/" .. clean
                    end

                    if opts.backup ~= false and fileExists(dest) then
                        hs.execute("/bin/cp " .. sq(dest) .. " " .. sq(dest .. ".bak"))
                    end

                    local destDir = dest:match("(.*)/")
                    if destDir then hs.execute("mkdir -p " .. sq(destDir)) end

                    local _, ok = hs.execute("/bin/cp " .. sq(staging .. "/" .. clean) .. " " .. sq(dest))
                    if ok then installed[#installed + 1] = clean
                    else failed[#failed + 1] = clean end
                end
            end

            rmrf(staging)

            if #installed == 0 then return nil, "Nothing could be installed." end

            -- A macro package shipping JSON needs compiling before it can bind.
            if manifest.type == "macro" and ms.compiler and ms.compiler.compile then
                for _, rel in ipairs(installed) do
                    if rel == "ms_macros_visual.json" then
                        pcall(function() ms.compiler.compile() end)
                        break
                    end
                end
            end

            -- A slot map is state, not a file the install root should keep:
            -- copying it in is what the loop above did, so read it back into
            -- ms.soundAssign and drop the stray copy. Without this the audio
            -- lands but every slot still points where it did before, which
            -- looks exactly like the import having silently failed.
            for _, rel in ipairs(installed) do
                if rel == "sound_assign.json" then
                    local dropped = _hsDir .. "/sound_assign.json"
                    local f = io.open(dropped, "r")
                    if f then
                        local raw = f:read("*all"); f:close()
                        local ok, tbl = pcall(hs.json.decode, raw)
                        if ok and type(tbl) == "table" then
                            ms.soundAssign = ms.soundAssign or {}
                            for slot, name in pairs(tbl) do
                                if type(slot) == "string" and type(name) == "string" then
                                    ms.soundAssign[slot] = name
                                end
                            end
                            if ms.saveSettings then pcall(ms.saveSettings) end
                        end
                    end
                    os.remove(dropped)
                    break
                end
            end

            -- Record the plugin in Guardian's ledger. Guardian blocks boot on
            -- any Spoons/ entry it has no record of, and this write is the
            -- only thing that creates one — which is the point: passing the
            -- trust gate above is what earns a Spoon the right to load, and a
            -- .spoon hand-dropped into the dir never gets here.
            if manifest.type == "plugin" then
                local names = {}
                for _, rel in ipairs(installed) do
                    local spoon = rel:match("^Spoons/([^/]+%.spoon)")
                    if spoon then names[spoon] = true end
                end
                if next(names) then
                    pcall(function() ms.package.recordPlugins(names, manifest) end)
                end
            end

            if manifest.type == "sound" or manifest.type == "profile"
                or manifest.type == "theme" then
                ms._soundsDirty = true
            end
            if manifest.type == "profile" then
                ms._profilesDirty = true
            end

            return {
                manifest  = manifest,
                installed = installed,
                failed    = failed,
                trust     = report.trust,
                warnings  = report.warnings,
            }
        end
    -- END Install --

    -- Plugin Inventory --
        -- What is installed, whether it is allowed to load, and taking it back
        -- out again. The ledger is the source for everything except the tree
        -- hash: a .spoon on disk carries no manifest of its own, so the record
        -- written at install time is the only thing that knows what a plugin
        -- is called or who wrote it.

        local function validSpoonName(name)
            if type(name) ~= "string" then return nil end
            if not name:match("^[%w%-%._ ]+%.spoon$") then return nil end
            if name:find("%.%.") or name:find("^%.") then return nil end
            return name
        end

        ms.package.validSpoonName = validSpoonName

        -- Disabled rather than enabled, deliberately. A freshly installed
        -- plugin should run without a second opt-in — the trust gate on the
        -- way in is the decision point — and a name this list has never heard
        -- of can never read as "off".
        ms.package.pluginEnabled = function(name)
            local off = ms._pluginsDisabled
            return not (type(off) == "table" and off[name] == true)
        end

        -- Every .spoon on disk, joined against the ledger. `status` is:
        --   ok           recorded, and the tree still hashes to its record
        --   modified     recorded, but the tree changed underneath it
        --   unrecorded   no ledger row — it did not come through install
        --
        -- The last two normally block boot in Guardian, so seeing one here
        -- means Guardian is off or the tree changed after it ran. The panel
        -- shows them either way: a list that quietly omitted the plugin that
        -- is about to stop the next boot would be the worst kind of correct.
        ms.package.listPlugins = function()
            local out = {}
            local spoonsDir = _hsDir .. "/Spoons"
            if not hs.fs.attributes(spoonsDir) then return out end

            local ledger = readLedger()
            local rows   = (ledger and ledger.plugins) or {}

            for entry in hs.fs.dir(spoonsDir) do
                local name = validSpoonName(entry)
                local abs  = spoonsDir .. "/" .. tostring(entry)
                local attr = name and hs.fs.attributes(abs)
                if name and attr and attr.mode == "directory" then
                    local rec    = rows[name]
                    local status = "unrecorded"
                    if type(rec) == "table" and type(rec.hash) == "string" then
                        local live = spoonTreeHash(abs)
                        status = (live and live:lower() == rec.hash:lower())
                            and "ok" or "modified"
                    end
                    rec = type(rec) == "table" and rec or {}

                    out[#out + 1] = {
                        dir         = name,
                        -- The bundle name minus ".spoon" is the fallback, so an
                        -- unrecorded plugin still reads as something.
                        name        = rec.name or name:gsub("%.spoon$", ""),
                        id          = rec.id,
                        version     = rec.version,
                        author      = rec.author,
                        website     = rec.website,
                        description = rec.description,
                        installedAt = rec.installedAt,
                        status      = status,
                        enabled     = ms.package.pluginEnabled(name),
                    }
                end
            end

            table.sort(out, function(a, b)
                return a.name:lower() < b.name:lower()
            end)
            return out
        end

        -- Disabling leaves the bundle exactly where it is. Moving or renaming
        -- it would change what Guardian sees in Spoons/ and turn an off switch
        -- into a blocked boot, so the flag is the only thing that moves.
        ms.package.setPluginEnabled = function(name, on)
            if not validSpoonName(name) then return false end
            ms._pluginsDisabled = ms._pluginsDisabled or {}
            ms._pluginsDisabled[name] = (on == false) or nil
            if ms.saveSettings then pcall(ms.saveSettings) end
            return true
        end

        -- Deletes the bundle and its ledger row together. Both or neither: a
        -- dir with no row blocks the next boot, and a row with no dir is a
        -- stale claim that would vouch for whatever lands under that name
        -- later. The disabled flag goes too, so reinstalling gives a plugin
        -- that is on rather than mysteriously off.
        ms.package.removePlugin = function(name)
            if not validSpoonName(name) then return false, "Invalid plugin name." end

            local abs  = _hsDir .. "/Spoons/" .. name
            local attr = hs.fs.attributes(abs)
            if not attr or attr.mode ~= "directory" then
                return false, "No such plugin."
            end

            hs.execute("/bin/rm -rf " .. sq(abs))
            if hs.fs.attributes(abs) then
                return false, "Could not remove " .. name .. "."
            end

            local ledger = readLedger()
            if ledger and ledger.plugins[name] then
                ledger.plugins[name] = nil
                writeLedger(ledger)
            end

            if ms._pluginsDisabled then ms._pluginsDisabled[name] = nil end
            if ms.saveSettings then pcall(ms.saveSettings) end

            -- The Spoon is already loaded into this session. Hammerspoon has
            -- no unload, so the files are gone but the code is not — say so
            -- rather than letting a still-running plugin look removed.
            return true
        end
    -- END Plugin Inventory --

    -- Export Helpers --
        -- Collects the live install's files for a given type, ready for pack().
        -- opts.configDir (profile kind only): read the config files from a saved
        -- profile directory instead of the live locations, so an inactive
        -- profile can be exported without switching to it. Sounds and fonts are
        -- NOT snapshotted per-profile, so those always come from the live dirs
        -- (config + live assets — a deliberate choice, see the Profiles panel).
        ms.package.collect = function(kind, opts)
            local files = {}

            local function addIf(rel, abs)
                if fileExists(abs) then files[rel] = abs end
            end

            local function addDir(relDir, absDir)
                if not hs.fs.attributes(absDir) then return end
                for entry in hs.fs.dir(absDir) do
                    if entry ~= "." and entry ~= ".." and not entry:find("^%.") then
                        local abs = absDir .. entry
                        if fileExists(abs) then files[relDir .. entry] = abs end
                    end
                end
            end

            if kind == "macro" then
                addIf("ms_macros.lua",         _hsDir .. "/ms_macros.lua")
                addIf("ms_macros_visual.json", _dataDir .. "/ms_macros_visual.json")
                addDir("sounds/macro/",        _hsDir .. "/sounds/macro/")

            elseif kind == "theme" then
                addIf("ms_theme.json", _dataDir .. "/ms_theme.json")
                addDir("ui/fonts/",    _hsDir .. "/ui/fonts/")
                -- Opt-out, not opt-in: sounds belong to the theme, so a theme
                -- export carries them unless the user has ticked them off.
                if ms.bundleSoundsWithTheme ~= false then
                    addDir("sounds/active/", _hsDir .. "/sounds/active/")
                    addDir("sounds/macro/",  _hsDir .. "/sounds/macro/")
                    local assign = ms.package.exportSoundAssign()
                    if assign then files["sound_assign.json"] = assign end
                end

            elseif kind == "sound" then
                addDir("sounds/active/", _hsDir .. "/sounds/active/")
                addDir("sounds/macro/",  _hsDir .. "/sounds/macro/")
                -- The audio without the slot map is a folder of files nobody
                -- has pointed at anything. The theme export has always sent
                -- both; this one used to send neither it nor a directory that
                -- exists.
                local assign = ms.package.exportSoundAssign()
                if assign then files["sound_assign.json"] = assign end

            elseif kind == "profile" then
                -- Config comes from a saved profile dir when exporting an
                -- inactive profile (all files flat in that dir), else the live
                -- split _hsDir / _dataDir layout.
                local cfg = opts and opts.configDir
                local macrosSrc = cfg and (cfg .. "ms_macros.lua")            or (_hsDir   .. "/ms_macros.lua")
                local dataSrc   = function(f) return cfg and (cfg .. f)       or (_dataDir .. "/" .. f) end
                addIf("ms_macros.lua",            macrosSrc)
                addIf("ms_macros_visual.json",    dataSrc("ms_macros_visual.json"))
                addIf("ms_settings.json",         dataSrc("ms_settings.json"))
                addIf("ms_settings_default.json", dataSrc("ms_settings_default.json"))
                addIf("ms_theme.json",            dataSrc("ms_theme.json"))
                -- Monolithic: carry the audio and fonts too, so an installed
                -- profile is the whole look and feel and not a config shell
                -- pointing at sounds and a font the recipient does not have.
                -- sounds/defaults/ is deliberately omitted (ships everywhere).
                addDir("sounds/active/", _hsDir .. "/sounds/active/")
                addDir("sounds/macro/",  _hsDir .. "/sounds/macro/")
                addDir("ui/fonts/",      _hsDir .. "/ui/fonts/")
                local assign = ms.package.exportSoundAssign()
                if assign then files["sound_assign.json"] = assign end
            end

            return files
        end

        -- Sound packages carry their slot assignment map alongside the audio.
        ms.package.exportSoundAssign = function()
            local path = tempDir("assign") .. "/sound_assign.json"
            if writeFile(path, hs.json.encode(ms.soundAssign or {})) then return path end
            return nil
        end
    -- END Export Helpers --

    -- Smoke Test --
        -- Round-trips the live theme through pack → verify → install and
        -- reports each leg. Run from the Hammerspoon console:
        --
        --   hs.inspect(ms.package.selfTest())
        --
        -- The theme is chosen deliberately: it is the smallest type, and the
        -- install leg rewrites ms_theme.json with the bytes it was packed
        -- from, so a pass leaves the install exactly as it found it.
        ms.package.selfTest = function()
            local steps = {}
            local function step(name, ok, detail)
                steps[#steps + 1] = { step = name, ok = ok and true or false, detail = detail }
                return ok
            end

            local out = tempDir("selftest") .. "/selftest-theme.mspkg"

            local files, count = ms.package.collect("theme"), 0
            for _ in pairs(files) do count = count + 1 end
            if not step("collect", files["ms_theme.json"] ~= nil,
                        files["ms_theme.json"] and (count .. " files")
                            or "no live ms_theme.json to pack") then
                return { ok = false, steps = steps }
            end

            local manifest, err = ms.package.pack({
                type    = "theme",
                name    = "Self-test Theme",
                version = "0.0.0",
                files   = files,
                out     = out,
            })
            if not step("pack", manifest ~= nil, err or (manifest and manifest.hash)) then
                return { ok = false, steps = steps }
            end

            local report = ms.package.verify(out)
            if not step("verify", report.ok, table.concat(report.issues, "; ")) then
                rmrf(out:match("(.*)/"))
                return { ok = false, steps = steps }
            end

            -- Unsigned by design — nothing here is in the validated library.
            step("trust", report.trust == "unsigned", "trust = " .. tostring(report.trust))

            -- backup = false: the install leg rewrites the same bytes it packed
            -- from, so .bak copies would be litter, not safety.
            local res, ierr = ms.package.install(out, { force = true, backup = false })
            step("install", res ~= nil, ierr or (res and table.concat(res.installed, ", ")))

            rmrf(out:match("(.*)/"))

            local allOk = true
            for _, s in ipairs(steps) do if not s.ok then allOk = false end end
            return { ok = allOk, steps = steps }
        end
    -- END Smoke Test --

end
