# vendor/ — everything the installer installs

The toolkit installs **only from this directory**. No install step fetches a
third-party repository, release asset or README; the only bytes that come off the
network are this repo itself, plus package registries whose artifacts are
verified against a lockfile hash.

`MANIFEST.json` records the sha256 of every file here, plus the upstream repo,
commit and license. `python3 scripts/vendor_manifest.py --check` verifies the
tree against it, and CI runs that on every push. `CHECKSUMS.sha256` is the same
data in `sha256sum -c` form, so the installer can verify a single file without
Python.

## What is here

| Path | Upstream | Pinned at | License |
|---|---|---|---|
| `mcp/angel-menu-mcp/` | [Jozkah/angel-menu-mcp](https://github.com/Jozkah/angel-menu-mcp) | `a96533e` | MIT |
| `tools/VTIL-Core/` | [vtil-project/VTIL-Core](https://github.com/vtil-project/VTIL-Core) | `9ebee8e` | BSD-3-Clause |
| `tools/NoVmp/` | [can1357/NoVmp](https://github.com/can1357/NoVmp) | `6c23c9a` | GPL-3.0 |
| `tools/NoVmp/VTIL-Core/` | submodule of NoVmp | `25861ca` | BSD-3-Clause |
| `tools/NoVmp/linux-pe/` | submodule of NoVmp | `30aae56` | **none** |
| `tools/vtil2/` | [pop-rip/vtil2](https://github.com/pop-rip/vtil2) | `242d331` | BSD-3-Clause |
| `tools/vmp-lazy-unpack/` | [x86rc/vmp-lazy-unpack](https://github.com/x86rc/vmp-lazy-unpack) | `66f64f6` | **none** |
| `tools/VMProtect-devirtualization/` | [JonathanSalwan/VMProtect-devirtualization](https://github.com/JonathanSalwan/VMProtect-devirtualization) | `d2b26d6` | **none** |
| `tools/web-mv/` | [Jozkah/web-mv](https://github.com/Jozkah/web-mv) | `73c4a0b` | **none** |
| `plugins/ponytail/` | [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) | `5.3.2` | MIT |
| `plugins/andrej-karpathy-skills/` | [multica-ai/andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills) | HEAD at vendoring | **none** |
| `bin/as_bundler`, `bin/as_bundler.exe` | as_bundler `v1.5.0` release | sha256 in `MANIFEST.json` | see upstream |
| `bin/echo-angelscript-lsp-0.0.10.zip` | echo-angelscript-lsp `0.0.10` release | sha256 | MIT |
| `scripts/esp_preview.as` | [speedsunderscore/echo-esp-preview](https://github.com/speedsunderscore/echo-esp-preview) | `f3f3834` | **none** |
| `docs/awesome-game-security.md` | gmh5225/awesome-game-security README | `4a3f1e7` | see upstream |
| `docs/gamehacking-cheatsheet.md` | ridpath/gamehacking-cheatsheet README | `e043efc` | see upstream |
| `npm/rea/` | `rea-agents@6.8.0` tarball + lockfile | sha256 | see upstream |
| `python/requirements.lock` | PyPI: triton-library, pefile, capstone, unicorn | sha256 per artifact | see upstream |
| `ARCHIVES` | mcp-gamehacking source tarball, split into 3 parts in this repo's releases | sha256 per part | MIT |

Submodules are inlined at the commits NoVmp's tree pins, so the build works
offline and reproducibly.

## Licensing — read before redistributing

Six upstreams ship **no license file**, which means all rights reserved by
default: `linux-pe`, `vmp-lazy-unpack`, `VMProtect-devirtualization`, `web-mv`,
`echo-esp-preview` and `andrej-karpathy-skills`. Vendoring them into a public
repository redistributes them. This repo is MIT; those directories are not
covered by it, and their presence here is not a license grant. If you are the
rights holder for one of them and want it removed, delete the directory — the
installer skips anything that is missing.

NoVmp is GPL-3.0 and stays in its own directory with its license intact. It is
aggregated, not linked into anything else in this repo.

## What is *not* vendored, and why

- **`mcp-gamehacking`** (3.1 GB git, 18 GB working tree, 4100+ skills). Vendored
  as a split archive in this repo's releases, not in git: GitHub blocks files
  over 100 MB, warns above 1 GB per repo, and every CI job would pay a
  multi-gigabyte checkout. `vendor/ARCHIVES` pins the parts by sha256 and
  `install.sh` verifies each one before extracting, then builds against the
  package-lock that ships inside the archive. `scripts/vendor_archive.sh`
  rebuilds it from the pinned commit.
- **Registry packages** — `npm ci` and `pip --require-hashes` fetch from the
  registry, but every artifact is verified against a lockfile hash, so the
  registry cannot substitute anything. That is the same guarantee as vendoring
  the bytes, without 300 MB of `node_modules` in git.

## Refreshing

```bash
# after moving a pin in tools.lock, re-vendor and re-record:
scripts/vendor_refresh.sh          # re-fetch the pinned sources into vendor/
python3 scripts/vendor_manifest.py --write
```

`echo update --lock` moves the pins; `scripts/vendor_refresh.sh` re-fetches the
trees; the manifest write is what makes CI accept the change.
