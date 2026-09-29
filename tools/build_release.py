#!/usr/bin/env python3
"""Build upgrade-safe ZIPs. Never include mutable game/project files."""
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
MOD_REL = Path('bin/x64/plugins/cyber_engine_tweaks/mods/LocationStudio')
MOD = ROOT / MOD_REL
VERSION = '0.78.0'
RUNTIME_DIRS = {'data', 'logs', 'bridge', 'exports', 'thumbnails'}
USER_DOCS = ('README.md', 'FIRST-RUN.md', 'AUTHORING-PLANS.md', 'MCP-EXAMPLES.md', 'TROUBLESHOOTING.md', 'IN-GAME-CHECK.md', 'NPC-WORKSPOTS.md', 'NPC-POPULATION.md', 'NPC-AI-ROUTES.md', 'COMBAT-ENCOUNTERS.md', 'COVER-NODES.md', 'WALKABILITY.md', 'NAVIGATION.md', 'DEVICE-LOGIC.md', 'QUEST-FORGE-ROUNDTRIP.md', 'QUEST-SIMULATION.md', 'WORLD-STATE-VARIANTS.md', 'INTERACTABLES.md', 'LIGHTING.md', 'VFX.md', 'ENVIRONMENT-PREVIEW.md', 'COLLISION-AUTHORING.md', 'SECTOR-INSPECTOR.md', 'PERFORMANCE-ANALYZER.md', 'OCCLUSION-VISIBILITY.md', 'LAYERS.md', 'SPLINES.md', 'TIMELINE.md', 'VANILLA-CLONE.md', 'REFERENCE-AREAS.md', 'ASSET-DEPENDENCIES.md', 'PREFLIGHT.md', 'ENVIRONMENT-DEFINITION-LANGUAGE.md', 'PROCEDURAL-GEOMETRY.md', 'MESH-RESOURCES.md', 'PARAMETRIC-ROOMS.md', 'MATERIAL-RESOURCES.md', 'CSG.md', 'COLLISION-RULES.md', 'GENERATED-BOUNDS.md', 'MESH-APPEARANCES-AND-DECALS.md', 'AMBIENT-AUDIO.md', 'VISUAL-REGRESSION.md', 'PROJECT-CHECKPOINTS.md', 'RUNTIME-SYNC.md', 'WB-ASSET-BOUNDS.md', 'WB-FAVORITES.md', 'WB-PREFAB-THUMBNAILS.md', 'WB-GENERATORS.md', 'WB-DEVICE-WIRING.md', 'WB-SCATTER-TYPES.md', 'WB-ARRAYS.md', 'WB-COMPATIBILITY.md', 'WB-PROJECT-BROWSER.md', 'WB-PROP-VALIDATORS.md', 'WB-HOTCYCLE.md', 'WB-ROOM-FRAMES.md', 'QUEST-FORGE-LINKS.md', 'CHANGELOG.md', 'LICENSE')


def packaged(path: Path) -> bool:
    if not path.is_file():
        return False
    relative = path.relative_to(ROOT)
    # The working tree can carry private execution checkpoints. They are not
    # project source and must never leak into a distributable source archive.
    if relative.parts and relative.parts[0] == '.remember':
        return False
    if '__pycache__' in relative.parts or path.suffix == '.pyc':
        return False
    if '.bak-' in path.name or path.name.endswith(('.bak', '.orig', '.rej')):
        return False
    if path.is_relative_to(MOD):
        mod_path = path.relative_to(MOD)
        if mod_path.parts[0] in RUNTIME_DIRS:
            return False
        # `build_worker` output is a machine-local .NET publish, never source.
        if 'wkit_worker' in mod_path.parts and {'publish', 'bin', 'obj'} & set(mod_path.parts):
            return False
    return path.is_file()


def build(output: Path) -> list[Path]:
    output.mkdir(parents=True, exist_ok=True)
    if output.is_relative_to(ROOT):
        raise ValueError('Release output must be outside the source tree')
    files = sorted(path for path in ROOT.rglob('*') if packaged(path))
    archives = []
    for flavor, source in [('upgrade-safe', False), ('source', True)]:
        archive_path = output / f'LocationStudio-v{VERSION}-game-resources-{flavor}.zip'
        with zipfile.ZipFile(archive_path, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
            prefix = Path('LocationStudio') if source else Path()
            for path in files:
                if source or path.is_relative_to(MOD):
                    archive.write(path, (prefix / path.relative_to(ROOT)).as_posix())
            for directory in sorted(RUNTIME_DIRS):
                relative = prefix / MOD_REL / directory
                archive.writestr(relative.as_posix() + '/', b'')
            for directory in ('logs', 'thumbnails'):
                archive.writestr((prefix / MOD_REL / directory / '.keep').as_posix(), b'')
            if not source:
                for name in USER_DOCS:
                    archive.write(ROOT / name, (MOD_REL / name).as_posix())
        with zipfile.ZipFile(archive_path) as archive:
            assert archive.testzip() is None
            assert not any(name.endswith(('project.json', 'config.json', '.log', '.pyc')) for name in archive.namelist())
            assert not any(name.endswith('.png') for name in archive.namelist())
        archives.append(archive_path)
    # Direct-folder build for users who already have the CET mod directory.
    # Its archive root is init.lua/modules/ui rather than bin/x64/..., which
    # prevents accidental nested installs such as LocationStudio/bin/x64/....
    direct_path = output / f'LocationStudio-v{VERSION}-direct-mod-folder.zip'
    with zipfile.ZipFile(direct_path, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        for path in files:
            if path.is_relative_to(MOD):
                archive.write(path, path.relative_to(MOD).as_posix())
        for directory in sorted(RUNTIME_DIRS):
            archive.writestr(directory + '/', b'')
        for directory in ('logs', 'thumbnails'):
            archive.writestr(directory + '/.keep', b'')
        for name in USER_DOCS:
            archive.write(ROOT / name, name)
    with zipfile.ZipFile(direct_path) as archive:
        assert archive.testzip() is None
        assert 'init.lua' in archive.namelist()
        assert not any(name.startswith('bin/') for name in archive.namelist())
        assert not any(name.endswith(('project.json', 'config.json', '.log', '.pyc')) for name in archive.namelist())
        assert not any(name.endswith('.png') for name in archive.namelist())
    archives.append(direct_path)
    checksums = output / f'LocationStudio-v{VERSION}-SHA256SUMS.txt'
    checksums.write_text(''.join(hashlib.sha256(path.read_bytes()).hexdigest() + '  ' + path.name + '\n' for path in archives), encoding='utf-8')
    return archives + [checksums]


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    for result in build(args.output.resolve()):
        print(f'{result.name}: {result.stat().st_size} bytes')
