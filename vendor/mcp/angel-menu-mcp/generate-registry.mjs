#!/usr/bin/env node
// generate-registry.mjs — auto-detect an Angel script's menu controls and emit the
// AI Menu Control registry for them. Names each control by its m_<var> variable (stable,
// meaningful), reads type / range / combo options / default straight from the ui::add_* call,
// and tracks the surrounding ui::add_tab / ui::add_category so the registry mirrors the overlay's
// own menu organization (tabs and categories).
//
// Usage:
//   node generate-registry.mjs <script.as>            # print the amc_build_registry() function
//   node generate-registry.mjs <script.as> --list     # just list detected controls (grouped)
//   node generate-registry.mjs <script.as> --json     # emit a JSON array of controls (for the mock / a web UI)
//   node generate-registry.mjs <script.as> --danger aim,chams,nosway   # extra danger names
//
// The default output is a paste-in AngelScript function. Pair it with the lane core
// (angel-menu-control.as). Re-run whenever the target's menu changes.

import { readFileSync } from "node:fs";

const args = process.argv.slice(2);
const file = args.find((a) => !a.startsWith("--"));
if (!file) {
  console.error("usage: node generate-registry.mjs <script.as> [--list] [--json] [--danger a,b,c]");
  process.exit(1);
}
const listOnly = args.includes("--list");
const jsonOnly = args.includes("--json");
// Emit only the writable kinds (check/slider/combo) — drop multi_select/color_picker. Use for a
// host whose lane has no multi/color set path (e.g. huntshowdown's uireg_* registry, which has no
// uireg_multi/uireg_color helpers and would fail to compile if they were emitted).
const writableOnly = args.includes("--writable-only");
const dIdx = args.indexOf("--danger");
const extraDanger = dIdx >= 0 && args[dIdx + 1] ? args[dIdx + 1].split(",").map((s) => s.trim()) : [];

const src = readFileSync(file, "utf8");

// Skip internal/plumbing variables and pure-position sliders — not "features".
const SKIP_PREFIX = ["m_pv_", "m_btn_", "m_pos_"];
// A control writes game memory if its name matches these — flags it danger (ui_set needs ARM).
const DANGER_RE = /(^|_)(aim|cham|chams|nosway|norecoil|nospread|force_bone|team_chams|team_cham)($|_)|^cv_/i;

const nameOf = (v) => v.replace(/^m_/, "");
const isSkipped = (v) => SKIP_PREFIX.some((p) => v.startsWith(p));
const isDanger = (v) => {
  const n = nameOf(v);
  return DANGER_RE.test(n) || extraDanger.includes(n);
};

// Split a top-level argument list (respects (), {}, "" nesting) into raw arg strings.
function splitArgs(s) {
  const out = [];
  let depth = 0, inStr = false, cur = "";
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (inStr) { cur += c; if (c === '"' && s[i - 1] !== "\\") inStr = false; continue; }
    if (c === '"') { inStr = true; cur += c; continue; }
    if (c === "(" || c === "{" || c === "[") depth++;
    if (c === ")" || c === "}" || c === "]") depth--;
    if (c === "," && depth === 0) { out.push(cur.trim()); cur = ""; continue; }
    cur += c;
  }
  if (cur.trim() !== "") out.push(cur.trim());
  return out;
}

// Grab the balanced (...) starting at index `open` ('('); returns {inner, end}.
function balanced(text, open) {
  let depth = 0, inStr = false;
  for (let i = open; i < text.length; i++) {
    const c = text[i];
    if (inStr) { if (c === '"' && text[i - 1] !== "\\") inStr = false; continue; }
    if (c === '"') { inStr = true; continue; }
    if (c === "(") depth++;
    else if (c === ")") { depth--; if (depth === 0) return { inner: text.slice(open + 1, i), end: i }; }
  }
  return null;
}

// Parse a brace list {"a","b",...} into label strings; null if it's not a literal list.
function parseOptionLabels(argRaw) {
  const m = argRaw.match(/\{([\s\S]*)\}/);
  if (!m) return null; // e.g. a variable like g_trait_filter_names — options unknown
  const labels = [];
  const re = /"((?:[^"\\]|\\.)*)"/g;
  let mm;
  while ((mm = re.exec(m[1]))) labels.push(mm[1].replace(/\\"/g, '"'));
  return labels;
}

// First string literal inside a raw arg list (used for tab/category names).
function firstStringLiteral(inner) {
  const m = inner.match(/"((?:[^"\\]|\\.)*)"/);
  return m ? m[1].replace(/\\"/g, '"') : "";
}
const parseBoolDefault = (raw) => (raw === undefined ? undefined : /^\s*true\s*$/i.test(raw) ? true : /^\s*false\s*$/i.test(raw) ? false : undefined);
const parseIntDefault = (raw) => {
  if (raw === undefined) return undefined;
  const m = raw.match(/-?\d+/);
  return m ? parseInt(m[0], 10) : undefined;
};

// One combined scan in source order over: ui::add_tab, ui::add_category, and the five control
// kinds. Tracking the running tab/category as we go stamps each control with its menu location.
const controls = [];
let curTab = "", curSub = "", curCat = "";
const scanRe = /\bui::add_tab\s*\(|\bui::add_subtab\s*\(|\bui::add_category\s*\(|\bm_([A-Za-z0-9_]+)\s*=\s*ui::add_(checkbox|slider|combobox|multi_select|color_picker)\s*\(/g;
let m;
while ((m = scanRe.exec(src))) {
  const openParen = scanRe.lastIndex - 1;
  const bal = balanced(src, openParen);
  if (!bal) continue;
  const matched = m[0];

  if (matched.startsWith("ui::add_tab")) {
    curTab = firstStringLiteral(bal.inner);
    curSub = ""; curCat = ""; // a new tab resets subtab + category context
    scanRe.lastIndex = bal.end + 1;
    continue;
  }
  if (matched.startsWith("ui::add_subtab")) {
    curSub = firstStringLiteral(bal.inner);
    curCat = ""; // a new subtab resets the category context
    scanRe.lastIndex = bal.end + 1;
    continue;
  }
  if (matched.startsWith("ui::add_category")) {
    curCat = firstStringLiteral(bal.inner);
    scanRe.lastIndex = bal.end + 1;
    continue;
  }

  const vvar = "m_" + m[1];
  const type = m[2];
  scanRe.lastIndex = bal.end + 1;
  if (isSkipped(vvar)) continue;
  const a = splitArgs(bal.inner);
  const name = nameOf(vvar);
  const label = firstStringLiteral(bal.inner) || name; // human menu label (the ui::add_* first arg)
  const danger = isDanger(vvar);
  const tab = curTab, subtab = curSub, category = curCat;

  if (type === "checkbox") {
    controls.push({ kind: "check", name, label, vvar, danger, tab, subtab, category, def: parseBoolDefault(a[1]) });
  } else if (type === "slider") {
    // ui::add_slider(label, def, min, max, step[, "unit"[, "key"]])
    controls.push({ kind: "slider", name, label, vvar, danger, tab, subtab, category, mn: a[2], mx: a[3], st: a[4], def: parseIntDefault(a[1]) });
  } else if (type === "combobox") {
    // ui::add_combobox(label, {opts}, default[, "key"])
    controls.push({ kind: "combo", name, label, vvar, danger, tab, subtab, category, opts: parseOptionLabels(a[1]), def: parseIntDefault(a[2]) });
  } else if (type === "multi_select") {
    controls.push({ kind: "multi", name, label, vvar, danger, tab, subtab, category, opts: parseOptionLabels(a[1]) });
  } else if (type === "color_picker") {
    controls.push({ kind: "color", name, label, vvar, danger, tab, subtab, category });
  }
}

// de-dup by name (first wins) — a well-formed menu shouldn't collide, but guard anyway
const seen = new Set();
let uniq = controls.filter((c) => (seen.has(c.name) ? false : (seen.add(c.name), true)));
if (writableOnly) uniq = uniq.filter((c) => c.kind === "check" || c.kind === "slider" || c.kind === "combo");

if (jsonOnly) {
  // Static default value where known; the runtime overwrites with the live value on ui_list.
  const defVal = (c) => {
    if (c.kind === "check") return c.def ?? false;
    if (c.kind === "slider") return c.def ?? (parseIntDefault(c.mn) ?? 0);
    if (c.kind === "combo") return c.def ?? 0;
    return c.kind === "color" ? "255,255,255,255" : 0;
  };
  // The web Menu Control lane only handles the writable kinds; multi/color are standalone-only
  // (read-only) and would fail the frontend's uiControl schema. Emit just check/slider/combo.
  const out = uniq
    .filter((c) => c.kind === "check" || c.kind === "slider" || c.kind === "combo")
    .map((c) => {
      const o = { name: c.name, label: c.label, kind: c.kind, value: defVal(c), danger: c.danger, writable: true, tab: c.tab, subtab: c.subtab, category: c.category };
      if (c.kind === "slider") { o.min = parseIntDefault(c.mn) ?? 0; o.max = parseIntDefault(c.mx) ?? 100; o.step = parseIntDefault(c.st) ?? 1; }
      if (c.kind === "combo") o.options = c.opts ?? [];
      return o;
    });
  console.log(JSON.stringify(out, null, 2));
  console.error(`\n[generate-registry] ${out.length} controls emitted from ${file}`);
  process.exit(0);
}

if (listOnly) {
  let lastTab = null, lastSub = null, lastCat = null;
  for (const c of uniq) {
    if (c.tab !== lastTab) { console.log(`\n== ${c.tab || "(no tab)"} ==`); lastTab = c.tab; lastSub = null; lastCat = null; }
    if (c.subtab !== lastSub) { console.log(`  > ${c.subtab || "(no subtab)"}`); lastSub = c.subtab; lastCat = null; }
    if (c.category !== lastCat) { console.log(`    [${c.category || "(no category)"}]`); lastCat = c.category; }
    let extra = "";
    if (c.kind === "slider") extra = ` [${c.mn}..${c.mx} step ${c.st}]`;
    else if (c.kind === "combo" || c.kind === "multi") extra = c.opts ? ` {${c.opts.join("|")}}` : " {opts: dynamic}";
    console.log(`      ${c.kind.padEnd(7)} ${c.name}${c.danger ? "  (danger)" : ""}${extra}`);
  }
  const byKind = uniq.reduce((o, c) => ((o[c.kind] = (o[c.kind] || 0) + 1), o), {});
  console.error(`\n${uniq.length} controls: ${JSON.stringify(byKind)}  danger: ${uniq.filter((c) => c.danger).length}`);
  process.exit(0);
}

// emit amc_build_registry() — interleave amc_tab()/amc_category() so the registry reads like the menu
const L = [];
L.push("// AUTO-GENERATED by generate-registry.mjs from " + file);
L.push("// Names come from the m_<var> globals; grouped by the overlay's own tabs/categories.");
L.push("// Re-run when the menu changes. Pair with angel-menu-control.as.");
L.push("void amc_build_registry()");
L.push("{");
const dstr = (c) => (c.danger ? ", true" : "");
const q = (s) => JSON.stringify(s ?? "");                 // safely-quoted AngelScript string literal
let lastTab = null, lastSub = null, lastCat = null;
for (const c of uniq) {
  if (c.tab !== lastTab) { L.push(`    amc_tab(${q(c.tab)});`); lastTab = c.tab; lastSub = null; lastCat = null; }
  if (c.subtab !== lastSub) { L.push(`    amc_subtab(${q(c.subtab)});`); lastSub = c.subtab; lastCat = null; }
  if (c.category !== lastCat) { L.push(`    amc_category(${q(c.category)});`); lastCat = c.category; }
  if (c.kind === "check") L.push(`    amc_check("${c.name}", ${c.vvar}, ${q(c.label)}${dstr(c)});`);
  else if (c.kind === "slider") L.push(`    amc_slider("${c.name}", ${c.vvar}, ${c.mn}, ${c.mx}, ${c.st}, ${q(c.label)}${dstr(c)});`);
  else if (c.kind === "combo") L.push(`    amc_combo("${c.name}", ${c.vvar}, "${(c.opts || []).join(",")}", ${q(c.label)}${dstr(c)});`);
  else if (c.kind === "multi") L.push(`    amc_multi("${c.name}", ${c.vvar}, "${(c.opts || []).join(",")}", ${q(c.label)}${dstr(c)});   // read-only`);
  else if (c.kind === "color") L.push(`    amc_color("${c.name}", ${c.vvar}, ${q(c.label)}${dstr(c)});   // read-only`);
}
L.push("}");
console.log(L.join("\n"));
console.error(`\n[generate-registry] ${uniq.length} controls emitted from ${file}`);
