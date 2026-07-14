    /* panel: console */
    (function() {
    "use strict";
// ── Badge labels ────────────────────────────────────────────────
            const LABELS = {
                print: "print",
                result: "result",
                error: "error",
                macro: "macro",
                input: "input",
                key: "key",
                mouse: "mouse",
                sound: "sound",
            };

            // ── Console buildRow ────────────────────────────────────────────
            function buildRow(entry) {
                const type = entry.type || "print";
                const ts = entry.ts || lp.nowTs();

                const row = document.createElement("div");
                row.className = "entry entry-" + type;

                const tsEl = document.createElement("span");
                tsEl.className = "ts";
                tsEl.textContent = ts;
                row.appendChild(tsEl);

                const badge = document.createElement("span");
                badge.className = "badge badge-" + type;
                badge.textContent = LABELS[type] ?? type;
                row.appendChild(badge);

                const msgEl = document.createElement("span");
                msgEl.className = "msg";

                if (type === "key") {
                    const arrow = entry.down ? "↓" : "↑";
                    msgEl.textContent = arrow + " " + (entry.key || entry.msg || "") + " (" + (entry.keyCode ?? "") + ")";
                } else if (type === "mouse") {
                    const arrow = entry.down ? "↓" : "↑";
                    const pos = (entry.x != null && entry.y != null) ? "  " + entry.x + "," + entry.y : "";
                    msgEl.textContent = arrow + " mouse:" + (entry.button ?? "") + pos;
                } else if (type === "sound" || type === "macro") {
                    msgEl.textContent = String(entry.msg ?? "");
                } else if (type === "input") {
                    msgEl.textContent = "> " + String(entry.msg ?? "");
                } else {
                    msgEl.textContent = String(entry.msg ?? "");
                }

                row.appendChild(msgEl);
                row.onmouseenter = function() { lp.playSlot("hover"); };
                row.onclick = lp._handleEntryClick;
                return row;
            }

            // ── Create LogPanel ─────────────────────────────────────────────
            const _panel = document.querySelector('.panel-console');
            const lp = createLogPanel({
                channel: "console",
                buildRow,
                container: _panel,
                maxEntries: 500,
                scrollThresh: 60,
            });

            // ── Expose globals for inline handlers ──────────────────────────
            window._panelPauseFns['console'] = lp.togglePause;
            window.playSlot    = lp.playSlot;
            window.closePanel  = lp.closePanel;
            window.consoleApplyTheme = lp.applyTheme;

            // ── Console-specific actions ────────────────────────────────────
            function doRun() {
                const input = document.getElementById("code-input");
                const code = input.value.trim();
                if (!code) return;
                lp.appendEntry({ ts: lp.nowTs(), type: "input", msg: code });
                lp.sendToHost({ action: "execute", code });
                input.value = "";
            }

            function doClear() {
                const log = _panel ? _panel.querySelector("#log") : document.getElementById("log");
                if (log) log.innerHTML = "";
                lp.sendToHost({ action: "clear" });
            }

            window.doRun   = doRun;
            window.doClear = doClear;
            window._panelClearFns['console'] = doClear;

            // ── Input bar: Enter to run ─────────────────────────────────────
            document
                .getElementById("code-input")
                .addEventListener("keydown", (e) => {
                    if (e.key === "Enter") {
                        e.preventDefault();
                        doRun();
                    }
                });

            // ── Init ────────────────────────────────────────────────────────
            document.addEventListener("DOMContentLoaded", () => {
                // Shell integration: register for incoming Lua pushes
                if (typeof registerPanel === "function") {
                    registerPanel("console", function(action, body) {
                        if (action === "appendEntry" && body) lp.appendEntry(body);
                        else if (action === "loadHistory" && body) lp.loadHistory(body);
                    });
                }
                // Strip window-chrome when embedded in shell
                if (window.shellPost) {
                    var p = document.getElementById("panel");
                    if (p) { p.style.borderRadius = "0"; p.style.clipPath = "none"; }
                }
                lp.sendToHost({ action: "ready" });
                document.getElementById("code-input").focus();
            });
    })();
