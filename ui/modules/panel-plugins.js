    /* panel: plugins */
    (function() {
    "use strict";

    /* ── panel-plugins.js ───────────────────────────────────────────────────
     *
     * The Plugins panel: what is installed under Spoons/, whether it is
     * allowed to load, and how to take it back out.
     *
     * Spoons/ is the only place in the install where third-party code runs, so
     * this panel is a trust surface before it is a list. Every card says three
     * separate things, and they are deliberately not collapsed into one
     * status: what the user asked for (the toggle), whether the record still
     * matches what is on disk (the pill), and whether it is actually running
     * right now (the note). A plugin can be on, recorded, and still not
     * running because it threw on load — a single "Active / Inactive" badge
     * would hide exactly the case worth surfacing.
     *
     * There is no Browse tab. The registry client is wired and the index is
     * signed, but it currently lists no plugins, and a tab that can only ever
     * say "nothing here" is a worse answer than not offering one.
     *
     * Building blocks come from window.msUI (panel-settings.js), same as
     * panel-theme.js. This panel owns only the card.
     */

    // ── State ────────────────────────────────────────────────────────────
    let S = {};

    function ui() { return window.msUI || null; }
    function playSlot(slot) { if (window.playSlot) window.playSlot(slot); }

    // Actions ride the plugins channel so they read as plugin actions in the
    // log; ms_ui.lua routes ui:plugins:* into the same handler set.
    function send(action, body) {
        if (!window.shellPost) return;
        window.shellPost("plugins", action, Object.assign({ action }, body || {}));
    }

    // ── Status vocabulary ────────────────────────────────────────────────
    // Keyed on ms.package.listPlugins()'s `status`. "ok" gets no pill: the
    // normal case should be quiet, or the two that are not stop standing out.
    const STATUS = {
        modified: {
            pill:  "danger",
            label: "Modified",
            note:  "The files changed after this plugin was installed. "
                 + "Guardian will block the next start until it is removed or "
                 + "re-imported.",
        },
        unrecorded: {
            pill:  "danger",
            label: "Unrecognized",
            note:  "This plugin was not installed through mudscript, so there "
                 + "is no record of where it came from. Guardian will block "
                 + "the next start until it is removed or re-imported.",
        },
    };

    // ── Card ─────────────────────────────────────────────────────────────
    function pluginCard(p) {
        const { h, toggle, actionBtn } = ui();
        const flagged = p.status !== "ok";

        const card = h("div", {
            cls: "plugin-card"
                + (flagged ? " flagged" : "")
                + (p.enabled ? "" : " off"),
            onmouseenter: () => playSlot("hover"),
        });

        // ── Identity ─────────────────────────────────────────────────────
        const name = h("div", { cls: "plugin-name" }, p.name || p.dir);
        const st = STATUS[p.status];
        if (st) name.appendChild(h("span", { cls: "pill " + st.pill }, st.label));
        if (!p.enabled) name.appendChild(h("span", { cls: "pill" }, "Off"));

        // Version, author and install date, in that order and only when known
        // — an unrecorded plugin has none of them, and "Unknown · Unknown"
        // reads as a broken panel rather than a missing record.
        const bits = [];
        if (p.version) bits.push("v" + p.version);
        if (p.author) bits.push("by " + p.author);
        bits.push(p.dir);
        if (p.installedAt) {
            const d = String(p.installedAt).slice(0, 10);
            if (d) bits.push("installed " + d);
        }

        const id = h("div", { cls: "plugin-card-id" },
            name,
            h("div", { cls: "plugin-meta", title: bits.join("  ·  ") }, bits.join("  ·  ")),
        );

        const top = h("div", { cls: "plugin-card-top" }, id);
        // A flagged plugin's toggle is pointless — it is not going to load
        // either way, and offering the switch implies it might.
        if (!flagged) {
            top.appendChild(toggle(p.enabled, (e) => {
                send("setPluginEnabled", { dir: p.dir, value: e.target.checked });
            }));
        }
        card.appendChild(top);

        if (p.description) {
            card.appendChild(h("div", { cls: "plugin-desc" }, p.description));
        }

        // ── Notes ────────────────────────────────────────────────────────
        // At most one, most urgent first. A modified plugin that also failed
        // to load does not need to be told twice.
        // Toggling now loads and tears down immediately, so "on but not
        // running" is no longer a waiting state — it means the load failed.
        if (st) {
            card.appendChild(h("div", { cls: "plugin-note danger" }, st.note));
        } else if (p.loadError) {
            card.appendChild(h("div", { cls: "plugin-note danger" },
                "Failed to load: " + p.loadError));
        } else if (p.enabled && !p.running) {
            card.appendChild(h("div", { cls: "plugin-note danger" },
                "Enabled, but not running. Reload to try again."));
        }

        // ── Actions ──────────────────────────────────────────────────────
        const actions = h("div", { cls: "plugin-actions" });
        actions.appendChild(actionBtn("Remove", "danger", () =>
            send("removePlugin", { dir: p.dir, label: p.name || p.dir })));
        if (p.website) {
            actions.appendChild(actionBtn("Website", "", () =>
                send("openURL", { url: p.website })));
        }
        card.appendChild(actions);

        return card;
    }

    // ── Body ─────────────────────────────────────────────────────────────
    function build(body) {
        const { h, groupLabel, btnRow, actionBtn } = ui();
        const list = Array.isArray(S.plugins) ? S.plugins : [];

        if (list.length === 0) {
            body.appendChild(h("div", { cls: "plugins-empty" },
                h("div", {}, "No plugins installed."),
                h("div", { style: "margin-top:8px" },
                    "Plugins run as code, so they can only be imported from "
                    + "the validated library."),
            ));
        } else {
            const flagged = list.filter((p) => p.status !== "ok");
            const clean   = list.filter((p) => p.status === "ok");

            // Flagged first, unlabelled. They are already loud, and a
            // "Needs attention" header above one card is filing, not warning.
            for (const p of flagged) body.appendChild(pluginCard(p));
            if (flagged.length && clean.length) {
                body.appendChild(groupLabel("Installed"));
            }
            for (const p of clean) body.appendChild(pluginCard(p));
        }

        body.appendChild(h("div", { style: "height:10px" }));
        body.appendChild(h("div", { cls: "section" },
            h("div", { cls: "section-body open", style: "padding-top:4px" },
                btnRow(
                    actionBtn("Import Plugin…", "", () =>
                        send("importPackage", {})),
                    actionBtn("Open Folder", "", () =>
                        send("openPluginsFolder", {})),
                ),
            ),
        ));
    }

    // ── Render ───────────────────────────────────────────────────────────
    function renderPluginsPanel(state) {
        if (state) S = state;
        if (!ui()) return; // panel-settings.js hasn't published the kit yet

        const el = document.getElementById("plugins-scroll");
        if (!el) return;
        const scrollTop = el.scrollTop;
        el.innerHTML = "";
        build(el);
        el.scrollTop = scrollTop;
    }
    window.renderPluginsPanel = renderPluginsPanel;

    })();
