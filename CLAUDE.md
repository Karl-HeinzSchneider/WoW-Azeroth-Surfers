# CLAUDE.md

Azeroth Surfers is a World of Warcraft addon (Lua 5.1 on Ace3) targeting WoW Forever
(`16001`), retail (`120100`) and Anniversary (2.5.6, interface 20506) through the TOC's `## Interface`, plus Node/TypeScript
tooling that checks, links and packages it. Anniversary (2.5.6, interface 20506) compatibility still needs in-client testing.

| Part                  | What it is                                                  | Details                                                      |
| --------------------- | ----------------------------------------------------------- | ------------------------------------------------------------ |
| `AzerothSurfers/`     | The addon; everything in it ships.                          | [AzerothSurfers/CLAUDE.md](AzerothSurfers/CLAUDE.md)         |
| `AzerothSurfers_Dev/` | Development tools, linked into a client, never released.    | [AzerothSurfers_Dev/CLAUDE.md](AzerothSurfers_Dev/CLAUDE.md) |
| `src/`                | Root tooling (Node 20+, TypeScript run by `tsx`, no build). | one file per `npm run` script                                |
| `tests/`              | Lua tests run without the client.                           | [docs/tests.md](docs/tests.md)                               |
| `.github/`            | Release workflows (BigWigs packager).                       | see "Releases"                                               |

A direct child directory with a same-named `.toc` is an addon; the tooling finds it on its own,
only `.pkgmeta` needs a `move-folders` line. An `AzerothSurfers_*` companion must declare
`## Dependencies: AzerothSurfers`. A development addon (`## X-AzerothSurfers-Dev:` in its TOC)
is never packaged and is listed in `.pkgmeta`'s `ignore`; debugging and biome-building tools go
there.

## Working on the code

No build step. `npm run dev:link -- "<WoW>/Interface/AddOns"` once (or `WOW_ADDONS_DIR`), then
`/reload` in-game. `/surfers` (or `/azerothsurfers`) opens the game on its title screen,
`/surfers options` the settings, `/surfers loglevel debug` the debug log, `/surfers auto` lets
the game play itself; with AzerothSurfers_Dev, `/surfers help` lists the dev tools.

## Commands (run from the root after `npm install`)

| Command                            | Does                                                                                                  |
| ---------------------------------- | ----------------------------------------------------------------------------------------------------- |
| `npm run check`                    | typecheck, addons, Lua syntax, XML schema, formatting. Run it before finishing a change.              |
| `npm run format`                   | Prettier on TS/JSON/Markdown/YAML, StyLua on Lua (XML is left to the editor). `format:check` reports. |
| `npm run check:addons`             | TOC and loader XML entries exist (`[TextLocale]` ones for every language), companions, no cycles.     |
| `npm run check:lua`                | `luac -p` on every addon Lua file (needs Lua 5.1 `luac` on PATH).                                     |
| `npm run check:xml`                | Every addon XML against Blizzard's `UI.xsd`; skipped without `../_data/BlizzardInterfaceCode`.        |
| `npm run test:game`                | `tests/simulation.lua`, `controls.lua`, `overlay.lua`, `leaderboard.lua` (needs `lua`).               |
| `npm run bench:overlay`            | WoW API calls per frame, offline.                                                                     |
| `npm run dev:link -- <AddOns dir>` | Links (junctions on Windows) every addon into a client; never replaces a path that isn't our link.    |
| `npm run package:addons`           | Deterministic `dist/AzerothSurfers-<version>.zip` without development addons and `CLAUDE.md` files.   |
| `npm run package:local`            | The release workflows' BigWigs packager, locally, no upload, into `.release/` (Windows: Git's bash).  |

`lua-language-server --check` uses `.luarc.json`; `lib/` is excluded from LuaLS, StyLua and
Prettier. Tooling code is ESM with `.js` extensions in relative imports, strict `tsc`.

## Releases

A pushed `v*` tag (`release-tag.yml`) or Actions > Run workflow (`release.yml`, `beta.yml`,
`alpha.yml`, which tag the head of `main`) run `package.yml`. `v1.1.0-beta1` is a beta,
`v1.1.0-alpha1` an alpha, anything else a release. The packager fills in
`## Version: @project-version@`.

**A new root file or folder that is not an addon must be added to `.pkgmeta`'s `ignore`**, or
it ships inside the addon. Uploads need the secrets `CF_API_KEY`, `WAGO_API_TOKEN`,
`WOWI_API_TOKEN` and the project ids in the TOC; a site without both is skipped.

## WoW addon constraints

- Lua 5.1 with Blizzard's restricted API: no `require`, `io`, `os`, or loading external files.
  Every code file must be in its addon's TOC or a loader XML it lists, in dependency order.
- Addons share one global namespace. Keep state in the private table; a file that uses it starts
  with

  ```lua
  ---@type string, AzerothSurfers
  local appName, app = ...
  ```

  (`local _, app = ...` when the name is unused). When a file adds a member to `app`, add a
  `---@field` to `AzerothSurfers/src/types.lua`.

- The only globals are the SavedVariables and XML-required mixins/frames, prefixed
  `AzerothSurfers…`.
- SavedVariables are populated after `ADDON_LOADED` (AceDB `OnInitialize` is the first safe
  place), never at file load.
- Ace3 types come from the `ketho.wow-api` VS Code extension, not from `lib/`; inherit from them
  rather than redeclaring the API.

## XML files

Every XML file starts with `<Ui xmlns="http://www.blizzard.com/wow/ui/">` and **no**
`xsi:schemaLocation` (validation comes from `.vscode/settings.json` and `npm run check:xml`). Lua
mixin files go in the TOC _before_ the XML that references them.

## Files with backslashes

Lua texture paths need `\\` (`"Interface\\Icons\\INV_Misc_Bag_10"`). Shell heredocs and inline
Python strip the doubled backslash; write such files with the Write/Edit tools.

## Reference data outside the repo (read, never edit, never copy in or list in a TOC)

- `../_data/BlizzardInterfaceCode/` (`ExportInterfaceFiles("code")`): exact API signatures,
  event payloads, templates, global strings. Prefer it over memory: this client's API differs
  from retail and Classic. Atlas names are only found in its XML usages.
- `../_data/BlizzardInterfaceArt/` (`ExportInterfaceFiles("art")`): every texture as `.blp`;
  verify texture paths (case-insensitive) and browse for icons by name.
- `../wow-listfile/parts/*.csv` (wowdev/wow-listfile): `id;Path` per line, by area (`world.csv`,
  `creature.csv`, `interface.csv`, `sound.csv`, ...). Search case-insensitively, e.g.
  `grep -i "woodendummies/.*\.m2$" ../wow-listfile/parts/world.csv`.

Only M2 models (`.m2`) can be shown: **a WMO's file id (`.wmo`) on a ModelScene actor crashes
the client**, so scenery built into a WMO cannot be used.

Only classic-era files; the path tells, not the id. Leave out anything under an expansion folder
(`Expansion01`, ...) and remakes beside originals (`..._Floating`, `WinterOrc`,
`Durotar_DryGrass`); an id much higher than its folder's neighbours is a later addition.

Creatures are named by display id, which the listfile lacks; a Wowhead classic NPC page has it:
`curl -sL -A "Mozilla/5.0" https://www.wowhead.com/classic/npc=3098 | grep -o "dataset.displayId = [0-9]*"`
(the Mottled Boar: 503). `/surfers animations <id>` (AzerothSurfers_Dev) shows its animations.

## Textures and Blizzard frames: reuse art, remake code

- **Don't create new textures unless there is no other way**; use the game's textures and
  atlases (the client does not load `.png`). Ask before drawing anything.
- **Don't hard-reference a retail or Classic frame**: don't inherit its templates, call its
  mixins, anchor to it or name it as the thing being copied. Remake the look with our own
  template and mixin; its art may be reused, and naming it as an example in a comment is fine.
- Shared client templates may be used directly, e.g. `PortraitFrameBaseTemplate`, after verifying
  they load on both supported clients. Forever-specific code (`Blizzard_*/Camelot/`) needs a
  shared alternative or a compatibility fallback on retail.
- A screenshot the user shares is a look reference, not a template to reproduce pixel by pixel.
