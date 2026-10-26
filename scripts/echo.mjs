#!/usr/bin/env node
// echo — the Echo toolkit CLI. One implementation for every platform.
//
//   echo update [flags]      update toolkit, profile, Pi, and the pinned tools
//   echo doctor              verify what is installed
//   echo status              one-screen summary
//   echo tools               list installed companion tools
//   echo version             versions of everything
//   echo help                this message
//
// update flags (Pi's own, passed straight through):
//   --extensions  --self  --models  --all  --force
// update flags (ours):
//   --tools   move installed tools to the pinned refs in tools.lock, then rebuild
//   --profile resync the Echo profile from the marketplace clone
//   --lock    re-resolve tools.lock to the current upstream heads, then update
//
// The launcher (`echo` with no subcommand) is a separate shim: it starts Pi with
// this profile. This file only handles the subcommands.

import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import {
  existsSync, mkdirSync, readFileSync, writeFileSync, copyFileSync,
  chmodSync, statSync, readdirSync, rmSync, renameSync, createWriteStream, createReadStream,
} from 'node:fs';
import { homedir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const SELF = fileURLToPath(import.meta.url);

const IS_WIN = process.platform === 'win32';
const HOME = homedir();
const ECHO_HOME = process.env.ECHO_HOME || join(HOME, '.local', 'share', 'echo-ai-toolkit');
const PROFILE = join(ECHO_HOME, 'pi');
const BIN_DIR = join(ECHO_HOME, 'bin');
const REF_DIR = join(ECHO_HOME, 'reference');
const LOCK = join(ECHO_HOME, 'tools.lock');
const PLUGIN = 'echo-ai-toolkit';
const CLI_VERSION = '1.1.0';

const TTY = process.stdout.isTTY && !process.env.NO_COLOR;
const paint = (code) => (s) => (TTY ? `\x1b[${code}m${s}\x1b[0m` : String(s));
const green = paint('1;32'), magenta = paint('1;35'), red = paint('1;31'), bold = paint('1');

const results = { ok: 0, skipped: [], failed: [] };
const say = (msg) => console.log(`\n${bold(`==> ${msg}`)}`);
const sub = (msg) => console.log(`    ${msg}`);
const ok = (msg) => { results.ok++; console.log(`    ${green('ok')}    ${msg}`); };
const skip = (msg, why) => { results.skipped.push(`${msg}: ${why}`); console.log(`    ${magenta('skip')}  ${msg} — ${why}`); };
const fail = (msg, why) => { results.failed.push(`${msg}: ${why}`); console.log(`    ${red('FAIL')}  ${msg} — ${why}`); };

function have(cmd) {
  return spawnSync(IS_WIN ? 'where' : 'which', [cmd], { stdio: 'ignore' }).status === 0;
}

function run(cmd, args, { timeout = 0, inherit = true, cwd = undefined } = {}) {
  const r = spawnSync(cmd, args, {
    stdio: inherit ? 'inherit' : 'pipe',
    encoding: 'utf8',
    timeout: timeout || undefined,
    shell: IS_WIN,
    cwd,
  });
  return { status: r.status, out: `${r.stdout || ''}${r.stderr || ''}` };
}

function capture(cmd, args) {
  const r = spawnSync(cmd, args, { stdio: ['ignore', 'pipe', 'pipe'], encoding: 'utf8', shell: IS_WIN });
  return { status: r.status, out: `${r.stdout || ''}${r.stderr || ''}` };
}

function countDirs(path) {
  try { return readdirSync(path, { withFileTypes: true }).filter((d) => d.isDirectory()).length; }
  catch { return 0; }
}

function countFiles(path, ext) {
  try { return readdirSync(path).filter((f) => f.endsWith(ext)).length; }
  catch { return 0; }
}

function sizeOf(path) {
  try { return statSync(path).size; } catch { return 0; }
}

// ── tools.lock ───────────────────────────────────────────────────────────────
const LOCK_HEADER = `# Echo AI Toolkit — tool lock.
#
# Pins every external artifact the installer fetches, so two installs a week
# apart are the same software. The installer reads this file and checks out the
# pinned ref; \`echo update --tools\` moves the installs to the pinned refs, and
# \`echo update --lock\` re-resolves them to the current upstream heads.
#
# Format: <kind> <name> <ref> <pin>
#   clone  <dir>            <owner/repo>  <commit sha>
#   raw    <filename>       <url>         <sha256 of the file>
#   asset  <filename>       <url>         <sha256 of the file>
#   npm    <package>        <package>     <version>
#   pip    <package>        <package>     <version>
#
# Columns are tab-free single spaces; names never contain spaces.
`;

// The repo copy wins when running from a checkout; the installed copy otherwise.
function lockPath() {
  const repoLock = join(dirname(SELF), '..', 'tools.lock');
  return existsSync(repoLock) ? repoLock : LOCK;
}

function readLock(path = lockPath()) {
  let text = '';
  try { text = readFileSync(path, 'utf8'); } catch { return []; }
  const rows = [];
  for (const line of text.split('\n')) {
    if (!line.trim() || line.trimStart().startsWith('#')) continue;
    const [kind, name, ref, pin] = line.split(/\s+/);
    if (kind && name && ref) rows.push({ kind, name, ref, pin: pin || '', line });
  }
  return rows;
}

const lockEntry = (rows, kind, name) => rows.find((r) => r.kind === kind && r.name === name);
const lockPin = (kind, name) => (lockEntry(readLock(), kind, name) || {}).pin || '';

function sha256(path) {
  return createHash('sha256').update(readFileSync(path)).digest('hex');
}

function verify(path, want) {
  if (!want) return true;
  try { return sha256(path) === want.toLowerCase(); } catch { return false; }
}

async function download(url, out) {
  const res = await fetch(url, { redirect: 'follow' });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  mkdirSync(dirname(out), { recursive: true });
  writeFileSync(out, Buffer.from(await res.arrayBuffer()));
}

// ── update ───────────────────────────────────────────────────────────────────
const PI_FLAGS = new Set(['--extensions', '--self', '--models', '--all', '--force']);

function usage() {
  const src = readFileSync(new URL(import.meta.url), 'utf8').split('\n');
  for (const line of src.slice(1)) {
    if (!line.startsWith('//')) break;
    console.log(line.replace(/^\/\/ ?/, ''));
  }
}

function parseArgs(argv) {
  const opts = { tools: false, profile: false, relock: false, pi: [], explicit: false };
  for (const a of argv) {
    if (a === '--tools') { opts.tools = true; opts.explicit = true; }
    else if (a === '--profile') { opts.profile = true; opts.explicit = true; }
    else if (a === '--lock') { opts.relock = true; opts.explicit = true; }
    else if (PI_FLAGS.has(a)) { opts.pi.push(a); opts.explicit = true; }
    else if (a === '-h' || a === '--help') { usage(); process.exit(0); }
    else {
      console.error(`${red(`unknown option: ${a}`)}`);
      console.error('run `echo update --help`');
      process.exit(2);
    }
  }
  if (!opts.explicit) {
    opts.tools = true; opts.profile = true; opts.pi = ['--all'];
  }
  // Pi-only requests must not touch the toolkit.
  if (opts.pi.length && !opts.profile && !opts.tools) {
    const piOnly = opts.pi.every((f) => f === '--self' || f === '--models');
    if (!piOnly) opts.profile = true;
  }
  return opts;
}

function updateToolkitPlugin() {
  if (!have('claude')) { skip('toolkit plugin', 'claude CLI not found'); return; }
  say('Toolkit plugin');
  if (run('claude', ['plugin', 'marketplace', 'update', PLUGIN], { timeout: 180000, inherit: false }).status === 0) {
    ok('marketplace updated');
  } else {
    skip('marketplace', 'update failed (offline?)');
  }
  if (run('claude', ['plugin', 'update', PLUGIN], { timeout: 180000, inherit: false }).status === 0) {
    ok('plugin updated');
  } else {
    skip('plugin', 'already current or update failed');
  }
}

function marketplaceClone() {
  const base = join(HOME, '.claude', 'plugins', 'marketplaces', PLUGIN);
  return existsSync(join(base, 'pi')) ? base : null;
}

function syncProfile() {
  say('Echo profile');
  const src = marketplaceClone();
  if (!src) { skip('profile', `marketplace clone not found at ~/.claude/plugins/marketplaces/${PLUGIN}`); return; }
  mkdirSync(join(PROFILE, 'prompts'), { recursive: true });
  mkdirSync(join(PROFILE, 'skills'), { recursive: true });
  for (const f of ['SYSTEM.md', 'APPEND_SYSTEM.md', 'AGENTS.md']) {
    if (existsSync(join(src, 'pi', f))) copyFileSync(join(src, 'pi', f), join(PROFILE, f));
  }
  const prompts = join(src, 'pi', 'prompts');
  if (existsSync(prompts)) {
    for (const f of readdirSync(prompts).filter((f) => f.endsWith('.md'))) {
      copyFileSync(join(prompts, f), join(PROFILE, 'prompts', f));
    }
  }
  let skills = 0;
  const skillsDir = join(src, 'skills');
  if (existsSync(skillsDir)) {
    for (const d of readdirSync(skillsDir, { withFileTypes: true }).filter((e) => e.isDirectory())) {
      const skill = join(skillsDir, d.name, 'SKILL.md');
      if (!existsSync(skill)) continue;
      mkdirSync(join(PROFILE, 'skills', d.name), { recursive: true });
      copyFileSync(skill, join(PROFILE, 'skills', d.name, 'SKILL.md'));
      skills++;
    }
  }
  ok(`profile resynced (${skills} skills, ${countFiles(join(PROFILE, 'prompts'), '.md')} templates)`);

  const launcher = join(src, 'pi', 'bin', IS_WIN ? 'echo.ps1' : 'echo');
  if (existsSync(launcher)) {
    mkdirSync(BIN_DIR, { recursive: true });
    copyFileSync(launcher, join(BIN_DIR, IS_WIN ? 'echo.ps1' : 'echo'));
    if (!IS_WIN) chmodSync(join(BIN_DIR, 'echo'), 0o755);
    ok('launcher refreshed');
  }
  // The subcommands live in this file, so it has to travel with the launcher —
  // together with the shims, so an older install is upgraded, not half-upgraded.
  mkdirSync(BIN_DIR, { recursive: true });
  copyFileSync(new URL(import.meta.url), join(BIN_DIR, 'echo.mjs'));
  for (const s of ['echo-update.sh', 'echo-doctor.sh', 'echo-update.ps1', 'echo-doctor.ps1']) {
    const from = join(src, 'scripts', s);
    if (!existsSync(from)) continue;
    copyFileSync(from, join(BIN_DIR, s));
    if (!s.endsWith('.ps1')) chmodSync(join(BIN_DIR, s), 0o755);
  }
  ok('cli refreshed');
}

// vendor/ is the source of truth for tool bytes: the installer copies from it and
// so does `echo update --tools`. Nothing here fetches a third-party host.
function vendorDir() {
  const local = join(dirname(SELF), '..', 'vendor');
  if (existsSync(join(local, 'MANIFEST.json'))) return local;
  const src = join(ECHO_HOME, 'src');
  try {
    const dir = readdirSync(src, { withFileTypes: true })
      .filter((d) => d.isDirectory() && d.name.startsWith('echo-ai-toolkit-'))
      .map((d) => join(src, d.name, 'vendor'))
      .find((v) => existsSync(join(v, 'MANIFEST.json')));
    return dir || null;
  } catch {
    return null;
  }
}

const VENDOR_SUB = {
  'mcp-gamehacking': 'mcp/mcp-gamehacking',
  'angel-menu-mcp': 'mcp/angel-menu-mcp',
  'VMProtect-devirtualization': 'tools/VMProtect-devirtualization',
  'vmp-lazy-unpack': 'tools/vmp-lazy-unpack',
  'web-mv': 'tools/web-mv',
  'signature-doctor': 'tools/signature-doctor',
  'VTIL-Core': 'tools/VTIL-Core',
  NoVmp: 'tools/NoVmp',
  vtil2: 'tools/vtil2',
};

const BUILD = {
  'mcp-gamehacking': null,
  'angel-menu-mcp': { cmd: 'npm', args: ['ci', '--omit=dev'] },
  'web-mv': { cmd: 'bun', args: ['install', '--frozen-lockfile'], cwd: 'relay' },
  'signature-doctor': { cmd: 'npm', args: ['ci', '--no-audit', '--no-fund'] },
  'VTIL-Core': { cmd: 'cmake', args: ['--build', 'build', '--config', 'Release'] },
  NoVmp: { cmd: 'cmake', args: ['--build', 'build', '--config', 'Release'] },
  vtil2: { cmd: 'dotnet', args: ['build', 'VTIL-Core.sln', '-c', 'Release'] },
};

function copyTree(src, dest) {
  // cp -R / robocopy via node: keep it dependency-free.
  mkdirSync(dest, { recursive: true });
  for (const entry of readdirSync(src, { withFileTypes: true })) {
    const from = join(src, entry.name);
    const to = join(dest, entry.name);
    if (entry.isDirectory()) copyTree(from, to);
    else if (entry.isFile()) copyFileSync(from, to);
  }
}

// mcp-gamehacking is 3.1 GB of git, so it ships as a split archive in this repo's
// releases. Same contract as the installer: verify every part, then extract.
async function installArchive(vendor) {
  const dir = join(ECHO_HOME, 'mcp-gamehacking');
  if (existsSync(join(dir, 'dist', 'index.js'))) { ok('mcp-gamehacking already installed'); return; }
  const meta = join(vendor, 'ARCHIVES');
  if (!existsSync(meta)) { skip('mcp-gamehacking', 'vendor/ARCHIVES missing'); return; }
  const parts = readFileSync(meta, 'utf8').split('\n')
    .filter((l) => l.trim() && !l.trimStart().startsWith('#'))
    .map((l) => l.trim().split(/\s+/))
    .filter((f) => f[0] === 'mcp-gamehacking')
    .map((f) => ({ url: f[1], sha: f[2] }));
  if (!parts.length) { skip('mcp-gamehacking', 'no archive parts listed'); return; }

  const tmp = join(ECHO_HOME, 'src', 'mcp-gamehacking');
  rmSync(tmp, { recursive: true, force: true });
  mkdirSync(tmp, { recursive: true });
  const files = [];
  for (const [i, part] of parts.entries()) {
    sub(`downloading archive part ${i + 1} of ${parts.length}…`);
    const out = join(tmp, `part${String(i + 1).padStart(2, '0')}`);
    try {
      const res = await fetch(part.url, { redirect: 'follow' });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      writeFileSync(out, Buffer.from(await res.arrayBuffer()));
    } catch (e) {
      fail('mcp-gamehacking', `part ${i + 1} download failed (${e.message})`);
      return;
    }
    if (!verify(out, part.sha)) { fail('mcp-gamehacking', `part ${i + 1} checksum mismatch`); return; }
    files.push(out);
  }

  const archive = join(tmp, 'archive.tar.gz');
  const sink = createWriteStream(archive);
  for (const f of files) {
    await new Promise((res, rej) => {
      const rs = createReadStream(f);
      rs.on('data', (c) => { if (!sink.write(c)) { rs.pause(); sink.once('drain', () => rs.resume()); } });
      rs.on('end', res);
      rs.on('error', rej);
    });
  }
  await new Promise((res) => sink.end(res));

  if (run('tar', ['-xzf', archive, '-C', tmp], { inherit: false }).status !== 0) {
    fail('mcp-gamehacking', 'extract failed');
    return;
  }
  const top = readdirSync(tmp, { withFileTypes: true })
    .filter((d) => d.isDirectory() && d.name.startsWith('mcp-gamehacking'))
    .map((d) => join(tmp, d.name))[0];
  if (!top) { fail('mcp-gamehacking', 'archive layout unexpected'); return; }
  rmSync(dir, { recursive: true, force: true });
  renameSync(top, dir);
  sub('building mcp-gamehacking (npm ci + build)…');
  if (run('npm', ['ci', '--silent'], { inherit: false, cwd: dir }).status !== 0) {
    fail('mcp-gamehacking', 'npm ci failed');
    return;
  }
  run('npm', ['run', 'build', '--silent'], { inherit: false, cwd: dir });
  if (existsSync(join(dir, 'dist', 'index.js'))) ok('mcp-gamehacking (verified archive, built)');
  else fail('mcp-gamehacking', 'missing dist/index.js after build');
}

async function updateTools() {
  say('Companion tools');
  const vendor = vendorDir();
  if (!vendor) { fail('vendor/', 'missing — clone the repo or run the installer'); return; }
  ok(`vendor/ ${vendor}`);
  await installArchive(vendor);

  for (const [name, subPath] of Object.entries(VENDOR_SUB)) {
    if (name === 'mcp-gamehacking') continue; // release archive, see vendor/ARCHIVES
    const src = join(vendor, subPath);
    const dir = join(ECHO_HOME, name);
    if (!existsSync(src)) { skip(name, `vendor/${subPath} missing`); continue; }
    try {
      if (existsSync(dir)) rmSync(dir, { recursive: true, force: true });
      copyTree(src, dir);
    } catch (e) {
      fail(name, `copy failed (${e.message})`);
      continue;
    }
    const build = BUILD[name];
    if (build && have(build.cmd)) {
      sub(`building ${name}…`);
      const cwd = build.cwd ? join(dir, build.cwd) : dir;
      if (run(build.cmd, build.args, { inherit: false, cwd }).status === 0) ok(`${name} (rebuilt)`);
      else fail(name, 'build failed');
    } else {
      ok(`${name} (vendored)`);
    }
  }

  // Binaries and READMEs come from vendor/ too.
  for (const [relPath, dest] of [
    ['scripts/esp_preview.as', join(REF_DIR, 'esp_preview.as')],
    ['docs/awesome-game-security.md', join(REF_DIR, 'awesome-game-security.md')],
    ['docs/gamehacking-cheatsheet.md', join(REF_DIR, 'gamehacking-cheatsheet.md')],
    [`bin/${IS_WIN ? 'as_bundler.exe' : 'as_bundler'}`, join(BIN_DIR, IS_WIN ? 'as_bundler.exe' : 'as_bundler')],
  ]) {
    const src = join(vendor, relPath);
    if (!existsSync(src)) { skip(basename(relPath), `vendor/${relPath} missing`); continue; }
    mkdirSync(dirname(dest), { recursive: true });
    copyFileSync(src, dest);
    if (relPath.startsWith('bin/') && !IS_WIN) chmodSync(dest, 0o755);
    ok(`${basename(relPath)} (vendored)`);
  }

  // Python packages: hash-pinned by vendor/python/requirements.lock.
  const venvPy = join(ECHO_HOME, 'venv', IS_WIN ? 'Scripts/python.exe' : 'bin/python');
  const req = join(vendor, 'python', 'requirements.lock');
  if (!existsSync(venvPy)) {
    skip('python packages', 'no venv');
  } else if (!existsSync(req)) {
    skip('python packages', 'vendor/python/requirements.lock missing');
  } else if (run(venvPy, ['-m', 'pip', 'install', '--quiet', '--disable-pip-version-check', '--require-hashes', '-r', req], { inherit: false }).status === 0) {
    ok('triton, capstone, pefile, unicorn (hash-pinned)');
  } else {
    skip('python packages', 'pip --require-hashes failed');
  }

  // rea-agents: vendored tarball + lockfile, so no npx resolution at runtime.
  const reaDir = join(ECHO_HOME, 'rea');
  const reaSrc = join(vendor, 'npm', 'rea');
  if (!existsSync(reaSrc)) {
    skip('rea', 'vendor/npm/rea missing');
  } else {
    try {
      if (existsSync(reaDir)) rmSync(reaDir, { recursive: true, force: true });
      copyTree(reaSrc, reaDir);
      if (run('npm', ['ci', '--silent'], { inherit: false, cwd: reaDir }).status === 0) ok('rea-agents (vendored, hash-pinned)');
      else fail('rea', 'npm ci failed');
    } catch (e) {
      fail('rea', `install failed (${e.message})`);
    }
  }
}

// ── update --lock: re-resolve every pin ──────────────────────────────────────
async function resolveGitHead(repo) {
  const r = capture('git', ['ls-remote', `https://github.com/${repo}`, 'HEAD']);
  const sha = r.out.split(/\s+/)[0];
  if (!/^[0-9a-f]{40}$/.test(sha)) throw new Error(`ls-remote failed for ${repo}`);
  return sha;
}

async function resolveLatestTag(repo) {
  const res = await fetch(`https://api.github.com/repos/${repo}/releases/latest`, {
    headers: { 'user-agent': 'echo-ai-toolkit', accept: 'application/vnd.github+json' },
  });
  if (!res.ok) throw new Error(`release lookup HTTP ${res.status}`);
  return (await res.json()).tag_name;
}

async function relock() {
  say('Re-resolving tools.lock');
  const rows = readLock();
  if (!rows.length) { fail('tools.lock', 'missing'); return; }
  const out = [];

  for (const row of rows) {
    try {
      if (row.kind === 'clone') {
        const sha = await resolveGitHead(row.ref);
        out.push({ ...row, pin: sha });
        ok(`${row.name} -> ${sha.slice(0, 7)}`);
      } else if (row.kind === 'npm') {
        const v = capture('npm', ['view', row.ref, 'version']).out.trim();
        if (!/^\d/.test(v)) throw new Error('npm view failed');
        out.push({ ...row, pin: v });
        ok(`${row.name} -> ${v}`);
      } else if (row.kind === 'pip') {
        const res = await fetch(`https://pypi.org/pypi/${row.ref}/json`);
        if (!res.ok) throw new Error(`pypi HTTP ${res.status}`);
        const v = (await res.json()).info.version;
        out.push({ ...row, pin: v });
        ok(`${row.name} -> ${v}`);
      } else if (row.kind === 'raw') {
        const m = row.ref.match(/^https:\/\/raw\.githubusercontent\.com\/([^/]+)\/([^/]+)\/[^/]+\/(.+)$/);
        if (!m) throw new Error('not a raw.githubusercontent URL');
        const sha = await resolveGitHead(`${m[1]}/${m[2]}`);
        const url = `https://raw.githubusercontent.com/${m[1]}/${m[2]}/${sha}/${m[3]}`;
        const tmp = join(ECHO_HOME, `.relock-${row.name}`);
        await download(url, tmp);
        const hash = sha256(tmp);
        out.push({ ...row, ref: url, pin: hash });
        ok(`${row.name} -> ${sha.slice(0, 7)} (${hash.slice(0, 12)}…)`);
      } else if (row.kind === 'asset') {
        const m = row.ref.match(/^(https:\/\/github\.com\/[^/]+\/[^/]+)\/releases\/download\/[^/]+\/(.+)$/);
        if (!m) throw new Error('not a release download URL');
        const repo = m[1].replace('https://github.com/', '');
        const tag = await resolveLatestTag(repo);
        const url = `${m[1]}/releases/download/${tag}/${m[2]}`;
        const tmp = join(ECHO_HOME, `.relock-${row.name}`);
        await download(url, tmp);
        const hash = sha256(tmp);
        out.push({ ...row, ref: url, pin: hash });
        ok(`${row.name} -> ${tag} (${hash.slice(0, 12)}…)`);
      } else {
        out.push(row);
      }
    } catch (e) {
      fail(row.name, e.message);
      out.push(row);
    }
  }

  const target = lockPath();
  const body = [LOCK_HEADER.trimEnd()];
  let prev = null;
  for (const r of out) {
    if (r.kind !== prev) {
      body.push('');
      if (r.kind === 'pip') body.push('# triton-library publishes pre-releases only; this is the current one.');
      prev = r.kind;
    }
    body.push([r.kind, r.name, r.ref, r.pin].join('\t'));
  }
  writeFileSync(target, body.join('\n') + '\n');
  ok(`wrote ${target}`);
  console.log('\n  Next: scripts/vendor_refresh.sh   (re-fetch vendor/ at the new pins)');
  console.log('        python3 scripts/vendor_manifest.py --write');
  console.log('        echo update --tools          (restore the installed tools from vendor/)');
}

// ── doctor ───────────────────────────────────────────────────────────────────
const rows = { ok: 0, miss: 0, na: 0 };
function row(status, label, detail = '') {
  rows[status]++;
  const tag = status === 'ok' ? green('ok  ') : status === 'miss' ? red('MISS') : magenta('n/a ');
  console.log(`  ${tag}  ${label.padEnd(28)} ${detail}`);
}

function doctor() {
  console.log(`\nEcho AI Toolkit — doctor`);
  console.log(`tools: ${ECHO_HOME}\n`);

  console.log('Plugin');
  if (have('claude')) {
    const list = capture('claude', ['plugin', 'list']).out;
    const id = (list.match(/echo-ai-toolkit@[\w-]+/) || [])[0];
    if (id) row('ok', 'echo-ai-toolkit plugin', id); else row('miss', 'echo-ai-toolkit plugin', 'run install.sh');
    for (const p of ['ponytail', 'andrej-karpathy-skills']) {
      if (list.includes(p)) row('ok', `${p} plugin`); else row('na', `${p} plugin`, 'optional');
    }
  } else {
    row('miss', 'claude CLI', 'https://claude.com/claude-code');
  }

  console.log('\nMCP servers');
  if (existsSync(join(ECHO_HOME, 'mcp.json'))) row('ok', 'mcp.json', join(ECHO_HOME, 'mcp.json'));
  else row('miss', 'mcp.json', 'run install.sh');
  if (existsSync(join(ECHO_HOME, 'mcp-gamehacking', 'dist', 'index.js'))) row('ok', 'mcp-gamehacking', 'built');
  else if (existsSync(join(ECHO_HOME, 'mcp-gamehacking'))) row('miss', 'mcp-gamehacking', 'cloned but not built');
  else row('miss', 'mcp-gamehacking', '~3.1 GB — run: echo update --tools');
  if (existsSync(join(ECHO_HOME, 'angel-menu-mcp', 'index.js'))) row('ok', 'angel-menu-mcp', 'installed');
  else row('miss', 'angel-menu-mcp', 'not installed');
  if (have('npx')) row('ok', 'rea (npx)', `pinned ${lockPin('npm', 'rea-agents') || 'unpinned'}`);
  else row('miss', 'rea (npx)', 'needs Node');
  if (have('r2pm')) row('ok', 'radare2 MCP', 'r2pm present');
  else row('na', 'radare2 MCP', 'needs radare2 (r2pm -Uci r2mcp)');
  if (have('uvx')) row('ok', 'ida MCP', 'uvx present');
  else row('na', 'ida MCP', 'needs uv (uvx ida-mcp) + IDA 9.4+');

  console.log('\nEcho tooling');
  const asPath = join(BIN_DIR, IS_WIN ? 'as_bundler.exe' : 'as_bundler');
  if (existsSync(asPath)) row('ok', 'as_bundler', asPath); else row('miss', 'as_bundler', 'not installed');
  const esp = [join(HOME, 'AppData', 'Roaming', 'scripts', 'esp_preview.as'), join(REF_DIR, 'esp_preview.as')].find(existsSync);
  if (esp) row('ok', 'esp_preview.as', esp); else row('miss', 'esp_preview.as', 'not installed');
  if (have('code')) {
    const ext = capture('code', ['--list-extensions']).out;
    if (/echo-angelscript-lsp/i.test(ext)) row('ok', 'echo-angelscript-lsp', 'VS Code extension');
    else row('miss', 'echo-angelscript-lsp', 'not installed');
  } else {
    row('na', 'echo-angelscript-lsp', 'VS Code not on PATH');
  }
  if (have('bun')) {
    if (existsSync(join(ECHO_HOME, 'web-mv', 'relay', 'node_modules'))) row('ok', 'web-mv', 'bun install done');
    else row('miss', 'web-mv', 'run install.sh');
  } else {
    row('na', 'web-mv', 'needs Bun');
  }

  console.log('\nPi coding agent');
  if (existsSync(join(PROFILE, 'SYSTEM.md'))) {
    row('ok', 'pi profile', PROFILE);
    row('ok', '  SYSTEM.md', `${sizeOf(join(PROFILE, 'SYSTEM.md'))} bytes (replaces default prompt)`);
    if (existsSync(join(PROFILE, 'APPEND_SYSTEM.md'))) {
      row('ok', '  APPEND_SYSTEM.md', `${sizeOf(join(PROFILE, 'APPEND_SYSTEM.md'))} bytes (appended)`);
    }
    row('ok', '  skills', `${countDirs(join(PROFILE, 'skills'))} ported`);
    row('ok', '  prompts', `${countFiles(join(PROFILE, 'prompts'), '.md')} templates`);
  } else {
    row('miss', 'pi profile', 'run install.sh');
  }
  const launcher = join(BIN_DIR, IS_WIN ? 'echo.ps1' : 'echo');
  if (existsSync(launcher)) row('ok', 'echo launcher', launcher); else row('miss', 'echo launcher', 'not installed');
  if (existsSync(join(BIN_DIR, 'echo.mjs'))) row('ok', 'echo cli', join(BIN_DIR, 'echo.mjs'));
  else row('miss', 'echo cli', 'not installed');
  if (have('pi')) row('ok', 'pi binary', capture('pi', ['--version']).out.split('\n')[0].trim());
  else row('na', 'pi binary', 'curl -fsSL https://pi.dev/install.sh | sh');
  const rcText = [join(HOME, '.bashrc'), join(HOME, '.zshrc')]
    .filter(existsSync).map((f) => readFileSync(f, 'utf8')).join('\n');
  if (rcText.includes('echo-ai-toolkit: echo alias')) row('ok', 'echo alias', 'in shell rc (shadows the builtin)');
  else row('na', 'echo alias', 'not added (ECHO_NO_ALIAS=1 or no rc file)');

  console.log('\nPython tooling');
  const venvPy = join(ECHO_HOME, 'venv', IS_WIN ? 'Scripts/python.exe' : 'bin/python');
  const py = existsSync(venvPy) ? venvPy : have('python3') ? 'python3' : have('python') ? 'python' : null;
  if (py) {
    if (run(py, ['-c', 'import triton'], { inherit: false }).status === 0) {
      const v = capture(py, ['-c', 'import importlib.metadata as m;print(m.version("triton-library"))']).out.trim();
      row('ok', 'triton', v || 'installed');
    } else {
      row('miss', 'triton', `pip install triton-library==${lockPin('pip', 'triton-library') || 'latest'}`);
    }
    if (existsSync(venvPy)) row('ok', 'python venv', join(ECHO_HOME, 'venv'));
    if (existsSync(join(ECHO_HOME, 'VMProtect-devirtualization'))) row('ok', 'VMProtect-devirtualization', 'cloned');
    else row('miss', 'VMProtect-devirtualization', 'not installed');
    if (existsSync(join(ECHO_HOME, 'vmp-lazy-unpack'))) row('ok', 'vmp-lazy-unpack', 'cloned');
    else row('miss', 'vmp-lazy-unpack', 'not installed');
  } else {
    row('na', 'python tooling', 'python not found');
  }

  console.log('\nCompiler-built tooling');
  for (const name of ['VTIL-Core', 'NoVmp', 'vtil2']) {
    if (existsSync(join(ECHO_HOME, name))) row('ok', name, 'source');
    else row('na', name, 'tier: full');
  }
  if (have('llvm-config') || have('opt')) {
    row('ok', 'LLVM', capture('llvm-config', ['--version']).out.trim() || 'present');
  } else {
    row('na', 'LLVM', 'only for Triton LLVM interface');
  }

  console.log('\nReference docs');
  for (const d of ['awesome-game-security', 'gamehacking-cheatsheet']) {
    const f = join(REF_DIR, `${d}.md`);
    if (existsSync(f) && sizeOf(f) > 0) row('ok', d, `${sizeOf(f)} bytes`);
    else row('miss', d, 'not fetched');
  }

  console.log('\nVendored tools');
  const vendor = vendorDir();
  if (vendor) {
    row('ok', 'vendor/', vendor);
    const missing = Object.entries(VENDOR_SUB)
      .filter(([name, sub]) => name !== 'mcp-gamehacking' && !existsSync(join(vendor, sub)))
      .map(([name]) => name);
    if (missing.length) row('miss', 'vendored trees', `${missing.length} missing: ${missing.join(', ')}`);
    else row('ok', 'vendored trees', 'every tool tree present');
  } else {
    row('miss', 'vendor/', 'missing — clone the repo');
  }

  console.log('\nPinned tools');
  const lock = readLock();
  if (!lock.length) {
    row('miss', 'tools.lock', 'missing — run install.sh');
  } else {
    row('ok', 'tools.lock', `${lock.length} pins`);
    // Tools are plain copies of vendor/, so "installed" means the tree is there.
    const absent = Object.keys(VENDOR_SUB).filter((name) => !existsSync(join(ECHO_HOME, name)));
    if (absent.length) row('miss', 'installed tools', `${absent.length} missing — run: echo update --tools`);
    else row('ok', 'installed tools', 'every vendored tool is installed');
  }

  console.log(`\n  ${green(rows.ok)} ok   ${red(rows.miss)} missing   ${magenta(rows.na)} not applicable\n`);
  if (rows.miss === 0) console.log('  Everything present.\n');
  else console.log('  Run ./install.sh to fill the gaps (ECHO_TIER=full for the compiler-built tools).\n');
}

// ── status / tools / version ────────────────────────────────────────────────
function status() {
  console.log(`\n${bold(`Echo toolkit`)}  ${ECHO_HOME}\n`);
  const line = (k, v) => console.log(`  ${k.padEnd(22)} ${v}`);
  line('profile', existsSync(join(PROFILE, 'SYSTEM.md')) ? green('ok') : 'missing');
  line('skills', countDirs(join(PROFILE, 'skills')));
  line('prompt templates', countFiles(join(PROFILE, 'prompts'), '.md'));
  line('launcher', join(BIN_DIR, IS_WIN ? 'echo.ps1' : 'echo'));
  line('pi', have('pi') ? capture('pi', ['--version']).out.split('\n')[0].trim() : 'not installed');
  if (have('claude')) {
    const id = (capture('claude', ['plugin', 'list']).out.match(/echo-ai-toolkit@[\w-]+/) || [])[0];
    line('claude plugin', id || 'not installed');
  }
  console.log(`\n  Run ${bold('echo doctor')} for the full picture.\n`);
}

function tools() {
  console.log(`\n${bold('Companion tools')}\n`);
  console.log(`  ${'TOOL'.padEnd(30)} ${'STATUS'.padEnd(10)} DETAIL`);
  console.log(`  ${'----'.padEnd(30)} ${'------'.padEnd(10)} ------`);
  const entries = [
    ['mcp-gamehacking', join(ECHO_HOME, 'mcp-gamehacking', 'dist', 'index.js'), 'built'],
    ['angel-menu-mcp', join(ECHO_HOME, 'angel-menu-mcp', 'index.js'), ''],
    ['as_bundler', join(BIN_DIR, IS_WIN ? 'as_bundler.exe' : 'as_bundler'), ''],
    ['esp_preview.as', join(REF_DIR, 'esp_preview.as'), ''],
    ['web-mv', join(ECHO_HOME, 'web-mv', 'relay', 'node_modules'), ''],
    ['VMProtect-devirtualization', join(ECHO_HOME, 'VMProtect-devirtualization'), ''],
    ['vmp-lazy-unpack', join(ECHO_HOME, 'vmp-lazy-unpack'), ''],
    ['VTIL-Core', join(ECHO_HOME, 'VTIL-Core'), ''],
    ['NoVmp', join(ECHO_HOME, 'NoVmp'), ''],
    ['vtil2', join(ECHO_HOME, 'vtil2'), ''],
    ['awesome-game-security', join(REF_DIR, 'awesome-game-security.md'), ''],
    ['gamehacking-cheatsheet', join(REF_DIR, 'gamehacking-cheatsheet.md'), ''],
  ];
  for (const [name, path, detail] of entries) {
    const present = existsSync(path);
    console.log(`  ${name.padEnd(30)} ${(present ? green('ok') : 'missing').padEnd(10)} ${present ? detail : ''}`);
  }
  console.log(`\n  Update with ${bold('echo update --tools')}\n`);
}

function version() {
  const clone = marketplaceClone();
  const head = clone ? capture('git', ['-C', clone, 'rev-parse', '--short', 'HEAD']).out.trim() : '';
  const line = (k, v) => console.log(`  ${k.padEnd(22)} ${v}`);
  console.log();
  line('echo', CLI_VERSION);
  line('toolkit', head || 'unknown');
  line('pi', have('pi') ? capture('pi', ['--version']).out.split('\n')[0].trim() : 'not installed');
  line('node', process.version);
  line('python', (have('python3') ? capture('python3', ['-V']).out : capture('python', ['-V']).out).replace(/^Python\s*/, '').trim() || 'not installed');
  console.log();
}

// ── dispatch ────────────────────────────────────────────────────────────────
async function main() {
  const [cmd, ...rest] = process.argv.slice(2);
  switch (cmd) {
    case 'update': {
      const opts = parseArgs(rest);
      console.log(`\n${bold('Echo update')}  ${new Date().toISOString().slice(0, 16).replace('T', ' ')}`);
      if (opts.relock) await relock();
      if (opts.profile || opts.tools) updateToolkitPlugin();
      if (opts.profile) syncProfile();
      if (opts.pi.length) {
        if (!have('pi')) skip('pi update', 'pi not installed');
        else {
          say(`Pi ${opts.pi.join(' ')}`);
          if (run('pi', ['update', ...opts.pi], { timeout: 600000 }).status === 0) ok(`pi update ${opts.pi.join(' ')}`);
          else skip('pi update', 'command failed (auth or network?)');
        }
      }
      if (opts.tools) await updateTools();
      console.log(`\n${bold('─'.repeat(60))}`);
      const tail = [`  ${green(`${results.ok} updated`)}`];
      if (results.skipped.length) tail.push(magenta(`${results.skipped.length} skipped`));
      if (results.failed.length) tail.push(red(`${results.failed.length} failed`));
      console.log(tail.join('   '));
      if (results.skipped.length) {
        console.log('\n  Skipped:');
        for (const s of results.skipped) console.log(`    · ${s}`);
      }
      if (results.failed.length) {
        console.log('\n  Failed:');
        for (const s of results.failed) console.log(`    · ${s}`);
      }
      console.log(`${bold('─'.repeat(60))}\n`);
      process.exit(results.failed.length ? 1 : 0);
    }
    case 'doctor': doctor(); break;
    case 'status': status(); break;
    case 'tools': tools(); break;
    case 'version': case '--version': case '-V': version(); break;
    case 'help': case '--help': case '-h': case undefined: usage(); break;
    default:
      console.error(`${red(`unknown command: ${cmd}`)}`);
      console.error('run `echo help`');
      process.exit(2);
  }
}

await main();
