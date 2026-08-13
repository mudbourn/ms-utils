    /* panel: browse */
    (function() {
    "use strict";

    /* ── panel-browse.js ────────────────────────────────────────────────────
     *
     * The Browse stage: the one universal storefront for the validated
     * library. Every package type — profile, plugin, theme, sound, macro —
     * is discovered and installed here, and here only. Management stays with
     * each type's own panel (a plugin toggles in Plugins, a theme applies in
     * Theme); this stage never manages, it only finds and installs.
     *
     * Trust comes off the registry entry and nowhere else: an entry is in the
     * signed index or it is not. We render the badge the entry carries and
     * hand the install to ms.package, which re-checks trust before it writes.
     *
     * Data is fetched lazily — the catalog is a network document with a TTL,
     * so we ask for it the first time the stage is opened rather than folding
     * it into the settings state that every panel repaint carries. Lua answers
     * 'browseList' with a 'catalog' push; a manual Refresh forces a refetch.
     *
     * Building blocks come from window.msUI (panel-settings.js), same as the
     * other module panels. This panel owns only its cards and toolbar.
     */

    // ── State ────────────────────────────────────────────────────────────
    let S = {
        entries:    null,   // null = never loaded; [] = loaded, empty
        loading:    false,
        error:      null,
        query:      "",
        type:       "all",
        loadedOnce: false,
    };

    function ui() { return window.msUI || null; }
    function playSlot(slot) { if (window.playSlot) window.playSlot(slot); }

    // Actions ride the browse channel so they read as browse actions in the
    // log; ms_ui.lua routes ui:browse:* into the same handler set.
    function send(action, body) {
        if (!window.shellPost) return;
        window.shellPost("browse", action, Object.assign({ action }, body || {}));
    }

    const TYPES = [
        { value: "all",     label: "All" },
        { value: "profile", label: "Profiles" },
        { value: "plugin",  label: "Plugins" },
        { value: "theme",   label: "Themes" },
        { value: "sound",   label: "Sounds" },
        { value: "macro",   label: "Macros" },
    ];


    // ── Data ─────────────────────────────────────────────────────────────
    function requestCatalog(opts) {
        S.loading = true;
        S.error   = null;
        render();
        send("browseList", Object.assign({ query: S.query, type: S.type }, opts || {}));
    }

    // Called by the rail button the first time this stage is shown.
    function ensureLoaded() {
        if (S.loadedOnce) return;
        S.loadedOnce = true;
        requestCatalog();
    }

    // ── Filtering ────────────────────────────────────────────────────────
    // Lua already filters, but re-filtering here keeps typing responsive
    // without a round-trip per keystroke: we narrow the last catalog locally
    // and only refetch on Refresh.
    function visible() {
        const all = expandForBrowse(S.entries);
        const q = S.query.trim().toLowerCase();
        return all.filter((e) => {
            if (S.type !== "all" && e.type !== S.type) return false;
            if (!q) return true;
            return (e.name || "").toLowerCase().includes(q)
                || (e.author || "").toLowerCase().includes(q)
                || (e.description || "").toLowerCase().includes(q);
        });
    }

    // Expand each profile that advertises components into virtual per-type
    // entries (Theme / Sound / Macro), so those slices show up under their own
    // filters and group headers — all installing from the profile's single
    // download, no duplicated assets. The profile itself stays in the list too.
    function expandForBrowse(list) {
        const out = [];
        for (const e of (Array.isArray(list) ? list : [])) {
            out.push(e);
            const c = (e.type === "profile" && e.components
                && typeof e.components === "object") ? e.components : null;
            if (!c) continue;
            // The card appends "[Type]" itself, so the virtual entry just
            // carries the profile's base name (its "profile" suffix stripped).
            const baseName = (e.name || e.id).replace(/\s+profile$/i, "");
            for (const k of ["theme", "sound", "macro"]) {
                if (!c[k]) continue;
                out.push({
                    id: e.id + "::" + k,   // synthetic — for keys/rendering only
                    installId: e.id,       // the real registry id to download
                    component: k,
                    virtual: true,
                    type: k,
                    name: baseName,
                    version: e.version,
                    author: e.author,
                    website: e.website,
                    url: e.url,            // shared asset → GitHub button works
                    sha256: e.sha256,
                    trust: e.trust,
                    themeBonus: (k === "theme") && !!c.sound
                        && !(c.theme && c.theme.includesSounds),
                });
            }
        }
        return out;
    }

    // Turn a package's asset URL into a human-facing GitHub page.
    // …/releases/download/<tag>/<asset>  →  …/releases/tag/<tag>
    // Any other github.com URL falls back to the owner/repo root. Non-GitHub
    // (or missing) URLs return null so the button simply does not appear.
    function githubPageFor(url) {
        if (typeof url !== "string") return null;
        let m = url.match(/^https:\/\/github\.com\/([^/]+)\/([^/]+)\/releases\/download\/([^/]+)\//);
        if (m) return "https://github.com/" + m[1] + "/" + m[2] + "/releases/tag/" + m[3];
        m = url.match(/^https:\/\/github\.com\/([^/]+)\/([^/]+)/);
        if (m) return "https://github.com/" + m[1] + "/" + m[2];
        return null;
    }

    // ── Card ─────────────────────────────────────────────────────────────
    function packageCard(e) {
        const { h, actionBtn } = ui();
        const card = h("div", {
            cls: "browse-card",
            onmouseenter: () => playSlot("hover"),
        });

        // Unified display name: "<base>  [Type]" for every kind — the profile
        // and its slices read the same way. Strip any type word the source name
        // already carries (a trailing "profile", or a " — Theme" from a virtual
        // entry) so it is never doubled.
        const typeLabel = String((TYPES.find((x) => x.value === e.type) || {}).label
            || e.type).replace(/s$/, ""); // "Themes" → "Theme"
        const baseName = (e.name || e.id)
            .replace(/\s*[—–-]\s*(Theme|Sound|Macro|Profile|Plugin)\s*$/i, "")
            .replace(/\s+(profile|theme|sound|macro|plugin)$/i, "")
            .trim() || (e.name || e.id);
        const displayName = baseName + "  [" + typeLabel + "]";

        // No trust badge: the registry is curator-published — every entry is
        // vetted before it lands, so presence in the library IS the trust
        // signal. install still re-checks trust before writing (ms.package).
        const name = h("div", { cls: "browse-name" }, displayName);

        const bits = [];
        bits.push(typeLabel);
        if (e.version) bits.push("v" + e.version);
        if (e.author)  bits.push("by " + e.author);

        const id = h("div", { cls: "browse-card-id" },
            name,
            h("div", { cls: "browse-meta", title: bits.join("  ·  ") },
                bits.join("  ·  ")),
        );
        card.appendChild(h("div", { cls: "browse-card-top" }, id));

        if (e.description) {
            card.appendChild(h("div", { cls: "browse-desc" }, e.description));
        }

        // A virtual entry is one slice of a profile (theme / sound / macro),
        // synthesised by expandForBrowse so it appears under its own type
        // filter. It installs from the profile's single download (installId +
        // component); everything else installs itself whole.
        const isVirtual = !!e.virtual;
        let includeThemeSounds = false;
        const installLabel = (e.type === "profile" && !isVirtual)
            ? "Install profile" : "Install";

        const actions = h("div", { cls: "browse-actions" });
        actions.appendChild(actionBtn(installLabel, "accent", () => {
            if (isVirtual) {
                send("browseInstall", {
                    id: e.installId,
                    component: e.component,
                    includeSounds: (e.component === "theme") ? includeThemeSounds : false,
                    label: e.name || e.id,
                });
            } else {
                send("browseInstall", { id: e.id, label: e.name || e.id });
            }
        }));
        if (e.website) {
            actions.appendChild(actionBtn("Website", "", () =>
                send("openURL", { url: e.website })));
        }
        // "View on GitHub" — the asset URL is a release download link; turn it
        // into the human-facing release page (…/releases/tag/<tag>), else fall
        // back to the repo root. Only shown for github.com-hosted packages.
        const ghHref = githubPageFor(e.url);
        if (ghHref) {
            actions.appendChild(actionBtn("GitHub", "", () =>
                send("openURL", { url: ghHref })));
        }
        card.appendChild(actions);

        // The theme slice's optional bonus: also pull the profile's audio.
        if (isVirtual && e.component === "theme" && e.themeBonus) {
            const bonus = h("label", { cls: "browse-bonus" });
            const cb = h("input", { type: "checkbox" });
            cb.addEventListener("change", () => { includeThemeSounds = cb.checked; });
            bonus.appendChild(cb);
            bonus.appendChild(h("span", {}, "Include sounds"));
            card.appendChild(bonus);
        }

        return card;
    }

    // ── Toolbar ──────────────────────────────────────────────────────────
    function toolbar() {
        const { h, seg, actionBtn } = ui();
        const bar = h("div", { cls: "browse-toolbar" });

        const search = h("input", {
            cls: "browse-search",
            type: "text",
            placeholder: "Search the library…",
            value: S.query,
            oninput: (ev) => { S.query = ev.target.value; renderResults(); },
        });
        bar.appendChild(search);

        bar.appendChild(seg(TYPES, S.type, (v) => { S.type = v; renderResults(); }));

        bar.appendChild(actionBtn("Refresh", "", () => {
            playSlot("interact");
            requestCatalog({ force: true });
        }));

        return bar;
    }

    // ── Results region ───────────────────────────────────────────────────
    function results() {
        const { h, groupLabel } = ui();
        const wrap = h("div", { cls: "browse-results" });

        if (S.loading && S.entries === null) {
            wrap.appendChild(h("div", { cls: "browse-empty" }, "Loading the library…"));
            return wrap;
        }
        if (S.error) {
            wrap.appendChild(h("div", { cls: "browse-empty" },
                h("div", {}, "Could not load the library."),
                h("div", { cls: "browse-empty-sub" }, S.error),
            ));
            return wrap;
        }

        const list = visible();
        if (list.length === 0) {
            const catalogEmpty = !Array.isArray(S.entries) || S.entries.length === 0;
            wrap.appendChild(h("div", { cls: "browse-empty" },
                h("div", {}, catalogEmpty
                    ? "The library has no packages yet."
                    : "No packages match your search."),
                h("div", { cls: "browse-empty-sub" }, catalogEmpty
                    ? "New profiles, plugins, themes, sounds and macros show up "
                    + "here once they are published to the validated library."
                    : "Try a different search or type filter."),
            ));
            return wrap;
        }

        // Group by type when browsing everything; a flat list otherwise.
        if (S.type === "all") {
            for (const t of TYPES) {
                if (t.value === "all") continue;
                const group = list.filter((e) => e.type === t.value);
                if (group.length === 0) continue;
                wrap.appendChild(groupLabel(t.label));
                for (const e of group) wrap.appendChild(packageCard(e));
            }
        } else {
            for (const e of list) wrap.appendChild(packageCard(e));
        }
        return wrap;
    }

    // ── Style ────────────────────────────────────────────────────────────
    // Self-contained so the panel reads correctly before any theme-specific
    // card CSS exists for it. Uses theme tokens only.
    function ensureStyle() {
        if (document.getElementById("browse-style")) return;
        const css = `
        /* Fill the stage so the results box below can own a bounded height and
           actually scroll. Without min-height:0 a flex child refuses to shrink
           and the overflow never engages. */
        #browse-root { display:flex; flex-direction:column; gap:0;
            height:100%; min-height:0; }
        #browse-results-box { flex:1 1 auto; min-height:0; overflow-y:auto; }
        .browse-toolbar { display:flex; gap:8px; align-items:center;
            padding:10px 14px; flex:0 0 auto;
            background:var(--bg); border-bottom:1px solid var(--border-dim); }
        .browse-search { flex:1 1 auto; min-width:0; padding:6px 10px;
            border:1px solid var(--border); border-radius:var(--radius-s);
            background:var(--surface); color:var(--text);
            font-family:inherit; font-size:13px; outline:none; }
        .browse-search:focus { border-color:var(--accent); }
        .browse-search::placeholder { color:var(--text3); opacity:1; }
        .browse-results { display:flex; flex-direction:column; gap:8px;
            padding:12px 14px; }
        .browse-card { border:1px solid var(--border-dim);
            border-radius:var(--radius); background:var(--surface);
            padding:10px 12px; display:flex; flex-direction:column; gap:8px; }
        .browse-card-top { display:flex; justify-content:space-between;
            align-items:flex-start; gap:8px; }
        .browse-name { font-weight:600; color:var(--text);
            display:flex; align-items:center; gap:8px; flex-wrap:wrap; }
        .browse-meta { color:var(--text3); font-size:11px; margin-top:3px; }
        .browse-desc { color:var(--text2); font-size:12px; line-height:1.45; }
        .browse-actions { display:flex; gap:8px; }
        .browse-bonus { display:flex; align-items:center; gap:6px;
            color:var(--text2); font-size:11px; cursor:pointer; user-select:none; }
        /* Custom checkbox — the native macOS control ignores our theme, so we
           strip its appearance and draw a themed box + check ourselves. */
        .browse-bonus input[type="checkbox"] { -webkit-appearance:none;
            appearance:none; margin:0; width:14px; height:14px; flex:0 0 14px;
            border:1px solid var(--border); border-radius:3px;
            background:var(--surface); cursor:pointer; position:relative;
            transition:background 0.12s, border-color 0.12s; }
        .browse-bonus input[type="checkbox"]:hover { border-color:var(--accent); }
        .browse-bonus input[type="checkbox"]:checked { background:var(--accent);
            border-color:var(--accent); }
        .browse-bonus input[type="checkbox"]:checked::after { content:"";
            position:absolute; left:4px; top:1px; width:4px; height:8px;
            border:solid var(--bg); border-width:0 2px 2px 0;
            transform:rotate(45deg); }
        .browse-empty { padding:40px 16px; text-align:center;
            color:var(--text2); }
        .browse-empty-sub { margin-top:8px; color:var(--text3);
            font-size:12px; line-height:1.5; max-width:34ch;
            margin-left:auto; margin-right:auto; }
        `;
        const el = document.createElement("style");
        el.id = "browse-style";
        el.textContent = css;
        document.head.appendChild(el);
    }

    // ── Render ───────────────────────────────────────────────────────────
    // Two seams: render() rebuilds the whole panel (toolbar + results);
    // renderResults() repaints only the list, so typing in the search box
    // never steals focus from the input.
    function render() {
        if (!ui()) return;
        const root = document.getElementById("browse-root");
        if (!root) return;
        ensureStyle();
        root.innerHTML = "";
        root.appendChild(toolbar());
        const box = document.createElement("div");
        box.id = "browse-results-box";
        box.appendChild(results());
        root.appendChild(box);
    }

    function renderResults() {
        if (!ui()) return;
        const box = document.getElementById("browse-results-box");
        if (!box) { render(); return; }
        box.innerHTML = "";
        box.appendChild(results());
    }

    // ── Bridge ───────────────────────────────────────────────────────────
    if (window.registerPanel) {
        window.registerPanel("browse", function(action, body) {
            if (action === "catalog") {
                S.entries = Array.isArray(body && body.entries) ? body.entries : [];
                S.loading = false;
                S.error   = (body && body.error) || null;
                render();
            } else if (action === "error") {
                S.loading = false;
                S.error   = (body && body.message) || "Unknown error.";
                render();
            }
        });
    }

    // Lazy first load: fetch the catalog the first time the stage is opened,
    // not at boot — the registry is a network document and most sessions
    // never open Browse.
    const railBtn = document.querySelector('.rail-item[data-panel="browse"]');
    if (railBtn) railBtn.addEventListener("click", ensureLoaded);

    window.renderBrowsePanel = render;

    })();
