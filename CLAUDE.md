# CLAUDE.md

Guidance for Claude Code when working in this repository. This file holds the map and the rules
that apply everywhere; the addon folder has its own `CLAUDE.md` with its load order and file map.

## What this is

Surfer is a World of Warcraft addon (Lua 5.1 on top of Ace3) for the client set by the
TOC's `## Interface` (`16001` = WoW Forever), plus the Node/TypeScript tooling that checks,
links and packages it.

| Part       | What it is                                                                                                                          | Details                              |
| ---------- | ----------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------ |
| `Surfer/`  | The addon: everything in it ships. Settings in `SurferDB`.                                                                          | [Surfer/CLAUDE.md](Surfer/CLAUDE.md) |
| `src/`     | Root tooling (Node 20+, TypeScript run by `tsx`, no build): check the addons, link them into a client, package them. Never shipped. | see "Tooling" below                  |
| `.github/` | The release workflows (BigWigs packager).                                                                                           | see "Releases" below                 |

A direct child directory with a same-named `.toc` is an addon; the tooling discovers addons that
way, so a second addon (e.g. an `Surfer_Options` companion) needs no registration in the
tooling — only a `move-folders` line in `.pkgmeta`. A companion named `Surfer_*` must
declare `## Dependencies: Surfer` (`npm run check:addons` enforces it).

## Working on the code

WoW addons are plain Lua/XML files loaded by the game; there is no build step. To try a change:
`npm run dev:link -- "<WoW>/Interface/AddOns"` (once; links every addon directory, also honors
`WOW_ADDONS_DIR`) and `/reload` in-game. `/surfer` opens the runner; `/surfer options` opens settings,
`/surfer loglevel debug` shows the debug log.

## Commands (Node 20+, run from the root after `npm install` once)

| Command                            | Does                                                                                                                                                                                                                                |
| ---------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `npm run check`                    | Everything below that validates, in order: typecheck, addons, Lua syntax, XML schema, formatting. Run it before finishing a change.                                                                                                 |
| `npm run format`                   | Prettier (`.prettierrc.json`, `.prettierignore`) on TS/JSON/Markdown/YAML, then StyLua (`stylua.toml`, `.styluaignore`) on Lua. Leaves XML to the editor. `npm run format:check` only reports.                                      |
| `npm run check:addons`             | Every TOC load entry exists (a `[TextLocale]` entry for every client language), `Surfer_*` companions depend on `Surfer`, no dependency cycles.                                                                                     |
| `npm run check:lua`                | `luac -p` on every addon Lua file (needs a Lua 5.1 `luac` on PATH).                                                                                                                                                                 |
| `npm run check:xml`                | Validates every addon XML against Blizzard's `UI.xsd` via python + lxml; skipped when `../_data/BlizzardInterfaceCode` is absent.                                                                                                   |
| `npm run typecheck`                | `tsc --noEmit` on `src/`.                                                                                                                                                                                                           |
| `npm run dev:link -- <AddOns dir>` | Symlink (junction on Windows) every addon into a client; refuses to replace a path that isn't already our link.                                                                                                                     |
| `npm run package:addons`           | Deterministic `dist/Surfer-<version>.zip` of all addons (gitignored), without `CLAUDE.md` files.                                                                                                                                    |
| `npm run package:local`            | The BigWigs packager the release workflows use (`.pkgmeta`), run locally without uploading: addon folders and zip in `.release/` (gitignored). Extra `release.sh` options go after `--`. On Windows it needs Git for Windows' bash. |

Static checks also used ad hoc: `lua-language-server --check` (config in `.luarc.json`; `lib/` is
excluded from LuaLS, StyLua and Prettier).

## Tooling (`src/`)

ESM with `.js` extensions in relative imports; `tsx` runs the `.ts` directly; strict `tsc`.

- `config.ts` — `ROOT`, `CLIENT_LOCALES` (every `[TextLocale]` value), `packageName()` (the
  `package-as` of `.pkgmeta`, used for zip names and as the main addon's name).
- `addons.ts` — `addonDirectories()` (every direct child with a same-named `.toc`),
  `addonVersion`, `walkFiles`.
- `check-addons.ts`, `check-lua.ts`, `check-xml.ts`, `link-addons.ts`, `package-addons.ts`,
  `package-local.ts` — one per `npm run` script above.
- `zip.ts` — `createZip` (stored, fixed timestamps), `directoryEntries`, `fileNamePart` (a TOC
  version as a file name), shared by the two packaging scripts.

## Releases

`.github/workflows/` runs the BigWigs packager on a pushed `v*` tag (`release-tag.yml`) and from
Actions > Run workflow (`release.yml`, `beta.yml`, `alpha.yml`, which tag the head of `main`
first); all four call `package.yml`. The tag decides the type: `v1.1.0-beta1` is a beta,
`v1.1.0-alpha1` an alpha, anything else a release. `## Version: @project-version@` in the TOC is
filled in by the packager.

What goes into the zip is set by `.pkgmeta` — **a new root file or folder that is not an addon
must be added to its `ignore` list**, or it ships inside the addon's folder. Uploads need the
repository secrets `CF_API_KEY`, `WAGO_API_TOKEN`, `WOWI_API_TOKEN` and the project ids in the TOC
(`## X-Curse-Project-ID`, `## X-Wago-ID`, `## X-WoWI-ID`); a site without both is skipped.

## WoW addon constraints

- Lua 5.1 with Blizzard's restricted API. No `require`, `io`, `os`, or `loadstring` of external
  files; every code file must be listed in its addon's TOC, in dependency order, or it will not
  load.
- Addons share one global namespace. Keep state in the private table passed to each file. A file
  that uses it starts with

  ```lua
  ---@type string, Surfer
  local appName, app = ...
  ```

  (`local _, app = ...` when the name is unused, or LuaLS flags it). The `---@type` line gives the
  language server completion on `app.*`. When a file adds a member to `app`, add a matching
  `---@field` to `Surfer/src/types.lua`.

- The only sanctioned globals are the SavedVariables tables and XML-required mixins/frames, which
  are prefixed `Surfer…`.
- Persistent state lives only in tables declared via `## SavedVariables`; they are populated after
  `ADDON_LOADED`, not at file-load time (AceDB `OnInitialize` is the first safe place).
- Ace3 types (`AceAddon`, `AceDBObject-3.0`, `AceDB.Schema`, …) come from the `ketho.wow-api`
  VS Code extension (`.vscode/settings.json` → `Lua.workspace.library`), not from `lib/`;
  inherit from them rather than redeclaring the API.

## XML files

Every XML file starts with `<Ui xmlns="http://www.blizzard.com/wow/ui/">` and **no**
`xsi:schemaLocation` — the client ignores it and a wrong path makes the VS Code XML extension
report errors. Schema validation comes from `xml.fileAssociations` in `.vscode/settings.json`
(mapping `**/*.xml` to `../_data/BlizzardInterfaceCode/.../Blizzard_SharedXML/UI.xsd`) and from
`npm run check:xml`. Lua mixin files must be listed in the TOC _before_ the XML that references
them.

## Files with backslashes

Lua strings for texture paths need `\\` (`"Interface\\Icons\\INV_Misc_Bag_10"`). Shell heredocs
and inline Python strip the doubled backslash; write such files with the Write/Edit tools (or a
script file with raw strings).

## Optional: Blizzard's own UI source and art for reference

A developer may place Blizzard's exported interface files in `../_data/` (a sibling of the repo,
`E:\Projects\_data\` here — outside the repo, so nothing needs gitignoring):

- `../_data/BlizzardInterfaceCode/` — from `/run ExportInterfaceFiles("code")`: Lua/XML of all
  FrameXML/AddOns.
- `../_data/BlizzardInterfaceArt/` — from `/run ExportInterfaceFiles("art")`: every texture as
  `.blp` under `BlizzardInterfaceArt/Interface/...`.

If they exist, **read them, never edit them**:

- Code: look up exact API signatures/return values, event payloads, frame templates and global
  strings. Prefer it over memory; this client's API differs from retail and from Classic.
- Art: verify that a texture path used in code exists (case-insensitive) and browse for suitable
  icons/textures by name. `.blp` can't be viewed; the file list is what matters. Atlas names
  (`atlas="..."`) are _not_ in the export — find them in XML usages under `BlizzardInterfaceCode`.

Never list anything from these folders in a TOC or copy files out of them into the repo.

## Textures and Blizzard frames: reuse art, remake code

- **Don't create new textures unless there is no other way.** Prefer the game's own textures
  and atlases (they scale with the frame and need no shipping; the client does not load `.png`).
  If something really must be drawn, ask first.
- **Don't hard-reference a frame from retail or Classic WoW.** Don't inherit its templates, call
  its mixins, anchor to its frames or name it as the thing being copied in comments or docs.
  Learn how it is built, then remake the look with our own template and mixin; naming it as "an
  example" in a comment is fine. Its _art_ (atlases, textures) may be reused freely.
- On WoW Forever, code the client itself ships (`Blizzard_*/Camelot/` and shared templates it
  loads such as `Blizzard_SharedXML`) may be leaned on directly: inheriting from e.g.
  `PortraitFrameBaseTemplate` or `PagingControlsTemplate` is fine. Verify the file is loaded by
  this client before depending on it.
- A screenshot the user shares is a look reference, not a template to reproduce pixel by pixel.
