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
--   sound    sounds/active/ and sounds/Default/, plus the slot assignment map
--   plugin   plugin.json plus the plugin's own lib/ Lua modules
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
            sound = {
                label    = "Sound Pack",
                paths    = { "sounds/active/", "sounds/Default/", "sound_assign.json" },
                required = { "sounds/active/", "sounds/Default/" },
            },
            plugin = {
                label    = "Plugin",
                paths    = { "plugin.json", "lib/" },
                required = { "plugin.json" },
            },
            -- No sounds/ here. Audio travels with the theme; a profile that
            -- also carried it would give two types a claim on the same files
            -- and make "which one wins on import" a coin toss.
            profile = {
                label    = "Profile",
                paths    = {
                    "ms_macros.lua", "ms_macros_visual.json", "ms_settings.json",
                    "ms_settings_default.json", "ms_theme.json",
                },
                required = {},
            },
        }

        ms.package.TYPES = { "macro", "theme", "sound", "plugin", "profile" }

        ms.package.spec = function(kind) return TYPE_SPECS[kind] end

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

        ms.package.pathAllowed = pathAllowed
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

        -- Returns a list of human-readable warnings; empty means clean.
        ms.package.compatWarnings = function(manifest)
            local warnings = {}
            if type(manifest) ~= "table" then return warnings end

            local fp   = manifest.platform or {}
            local here = ms.package.fingerprint()

            if fp.os and fp.os ~= "" and fp.os ~= here.os then
                warnings[#warnings + 1] =
                    "Built on " .. tostring(fp.os) .. ", importing on " .. here.os ..
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

            local req = (manifest.requires or {}).mudscript
            if type(req) == "string" and req ~= "" then
                local want = req:match("(%d+%.%d+%.%d+)")
                local have = tostring(ms.version or ""):match("(%d+%.%d+%.%d+)")
                if want and have and have < want then
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
            for _, rel in ipairs(ms.package.contents(path)) do
                if not safeRelPath(rel) then
                    result.issues[#result.issues + 1] = "Unsafe path in package: " .. rel
                elseif not manifest.legacy and not pathAllowed(manifest.type, rel) then
                    result.issues[#result.issues + 1] =
                        "File not permitted in a " .. manifest.type .. " package: " .. rel
                end
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

            -- At least one of the type's required paths must be present.
            if #spec.required > 0 then
                local satisfied = false
                for _, req in ipairs(spec.required) do
                    for rel in pairs(manifest.contents) do
                        if rel == req or (req:find("/$") and rel:sub(1, #req) == req) then
                            satisfied = true; break
                        end
                    end
                    if satisfied then break end
                end
                if not satisfied then
                    rmrf(staging)
                    return nil, "A " .. kind .. " package needs " ..
                        table.concat(spec.required, " or ") .. "."
                end
            end

            if kind == "macro" then
                local hasLua  = manifest.contents["ms_macros.lua"] ~= nil
                local hasJSON = manifest.contents["ms_macros_visual.json"] ~= nil
                manifest.macroFormat = (hasLua and hasJSON) and "both"
                    or (hasJSON and "json" or "lua")
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
            if report.trust == "unsigned" and not opts.force then
                return nil, "Package is not in the validated library. Import anyway to continue."
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

    -- Export Helpers --
        -- Collects the live install's files for a given type, ready for pack().
        ms.package.collect = function(kind)
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
                addDir("sounds/active/",  _hsDir .. "/sounds/active/")
                addDir("sounds/Default/", _hsDir .. "/sounds/Default/")

            elseif kind == "profile" then
                addIf("ms_macros.lua",            _hsDir .. "/ms_macros.lua")
                addIf("ms_macros_visual.json",    _dataDir .. "/ms_macros_visual.json")
                addIf("ms_settings.json",         _dataDir .. "/ms_settings.json")
                addIf("ms_settings_default.json", _dataDir .. "/ms_settings_default.json")
                addIf("ms_theme.json",            _dataDir .. "/ms_theme.json")
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
