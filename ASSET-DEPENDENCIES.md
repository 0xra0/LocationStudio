# Asset dependency resolver

LocationStudio 0.69 resolves every resource your exported objects use and finds, recursively, what has to ship with the mod. It flags missing dependencies **before** the build. It runs in the MCP server (`dependency_*` tools and the Build Mod `dependencies` stage), and the result shows in **Spatial → Dependencies**.

## What is scanned

The resolver starts from every object that will be exported. Objects on export-disabled layers (such as Debug) and reference-area items are skipped. From each object it collects:
- depot paths anywhere in its template and World Builder data: `.mesh`, `.ent`, `.app`, `.mi`, `.mt`, `.mlsetup`, `.xbm`, `.particle`, `.effect`, `.anims`, `.workspot`, `.inkatlas`, …;
- TweakDB records (Entity Record objects, NPC population records);
- audio events (Static Audio Emitters, ambient audio).

Each reference is then followed recursively:

| Status | Meaning | Ships? |
| --- | --- | --- |
| `project` | found in your mod sources; its own references are followed | yes |
| `project_archive` | inside a prebuilt `.archive` you supplied; its dependency table is followed | yes (the archive) |
| `vanilla` | its path hash is in the game's content archives | no |
| `other_mod` | provided by an installed mod archive; listed under *external requirements* | no, users need that mod |
| `dynamic` | ArchiveXL substitution path (`*`, `{gender}`…), resolved at runtime | no |
| `missing` | none of the above; **blocks the build** | — |
| `unknown` | not in the sources and there is no vanilla index to decide | — |
| `unverified` | TweakDB records or audio events not defined by your sources or installed TweakXL mods; assumed vanilla, because the vanilla TweakDB and Wwise banks are not indexed | no |

Every missing file comes with the **chain** from the object that needs it, for example `Chair → chair.mesh → chair.mi → chair_d.xbm`.

## Mod sources

Put your modded files where the resolver looks. It searches, in order:
1. the `sources` you pass to a tool;
2. `LOCATION_STUDIO_MOD_SOURCES` (paths separated by your OS path separator);
3. `mod_sources/` in this mod folder;
4. during a build, the build workspace.

Each source can be:
- a folder laid out by depot path (`mymod/props/chair.mesh`);
- a **WolvenKit project**: `source/archive` is read as cooked CR2W and `source/raw` as WolvenKit JSON (`chair.mesh.json`). `source/resources/r6/tweaks/*.yaml` defines TweakXL records, and `customSounds/info.json` defines custom sound events;
- a prebuilt `.archive`.

References are read from WolvenKit JSON through every `DepotPath`, including hashed ones, and from cooked CR2W files through the depot-path strings of their import table. For TweakXL records, depot paths in the record block and `$base` records are followed.

## The vanilla index

Run `dependency_index_build` once, and again after each game update. It reads the RDAR index of every archive in `archive/pc/content` and `archive/pc/ep1` and caches their FNV-1a64 path hashes in `data/vanilla-archive-index.bin`. The files themselves are never extracted.

Without the index, anything that is not in your sources is reported as `unknown` rather than `missing`, and the build is not blocked. Installed mod archives (`archive/pc/mod`) and TweakXL YAML (`r6/tweaks`) are read at scan time.

## Tools

- `dependency_scan(premise_id, sources, workspace_name)` returns the full report: counts, missing files with chains, what ships, external requirements, unverified references, and per-object results. It also writes `exports/dependency-report.json`; in game, click **LOAD LATEST REPORT**, then **SELECT** an object that has missing dependencies.
- `dependency_check(references)` resolves specific paths, records (`Category.Name`) or `audio:event` names, for example before registering a modded asset.
- `dependency_stage(workspace_name)` copies everything that ships into a build workspace:
  - cooked files go to `source/archive`;
  - raw JSON goes to `source/raw`, where it still needs converting;
  - TweakXL YAML goes to `resources/r6/tweaks`;
  - prebuilt archives go next to the mod;
  - custom sounds go to `customSounds`.

## Build Mod

`build_mod_from_project` now runs a **dependencies** stage after preparing the workspace. It stages the shippable files and writes `automation/dependency-report.json`. It stops the build when anything is missing, or when a dependency exists only as raw JSON.

Pass `allow_missing_dependencies=true` only after telling the user exactly which files are missing; the build will then ship without them.
