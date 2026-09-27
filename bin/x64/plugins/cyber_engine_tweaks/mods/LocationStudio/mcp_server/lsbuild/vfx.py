"""Carry LocationStudio VFX scale/emission into World Builder native exports.

World Builder spawns and exports particle/effect nodes at scale 1:1. The
authored scale lives in the saved project (``metadata.vfx.scale``); this module
matches each saved VFX object to its exported ``worldStaticParticleNode`` /
``worldEffectNode`` by resource path and position and writes the scale into the
node's world transform, which the native sector writer copies to ``Scale``.
"""
from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Any

NODE_TYPES = {"particle": "worldStaticParticleNode", "effect": "worldEffectNode"}
RESOURCE_FIELD = {"worldStaticParticleNode": "particleSystem", "worldEffectNode": "effect"}
MATCH_DISTANCE = 0.1
SCALE_RANGE = (0.01, 100.0)


def _nodes(export: dict[str, Any]) -> list[dict[str, Any]]:
    return [n for s in export.get("sectors", []) if isinstance(s, dict)
            for n in s.get("nodes", []) if isinstance(n, dict)]


def _node_resource(node: dict[str, Any]) -> str:
    field = RESOURCE_FIELD.get(str(node.get("type")))
    ref = ((node.get("data") or {}).get(field) or {}) if field else {}
    return str(((ref.get("DepotPath") or {}).get("$value")) or "")


def _distance(a: dict[str, Any], b: dict[str, Any]) -> float:
    return math.sqrt(sum((float(a.get(k, 0) or 0) - float(b.get(k, 0) or 0)) ** 2 for k in "xyz"))


def _scale(value: Any) -> dict[str, float] | None:
    if not isinstance(value, dict):
        return None
    out: dict[str, float] = {}
    for axis in "xyz":
        n = value.get(axis)
        if isinstance(n, bool) or not isinstance(n, (int, float)) or not math.isfinite(n):
            return None
        if not SCALE_RANGE[0] <= float(n) <= SCALE_RANGE[1]:
            return None
        out[axis] = float(n)
    return out


def apply(project_file: str | Path, export_file: str | Path, *, write: bool = False,
          output: str | Path | None = None) -> dict[str, Any]:
    """Match saved VFX objects to exported nodes; with write=True set node scale in place.

    Objects absent from the export are reported as ``unmatched`` warnings: a
    premise/scene-scoped export legitimately leaves other effects out. A saved
    object with invalid scale or an ambiguous match is an error.
    """
    project = json.loads(Path(project_file).read_text(encoding="utf-8"))
    export_path = Path(export_file)
    export = json.loads(export_path.read_text(encoding="utf-8"))
    rows = []
    for obj in project.get("objects", []):
        cfg = (obj.get("metadata") or {}).get("vfx") if isinstance(obj, dict) else None
        if isinstance(cfg, dict) and obj.get("enabled") is not False:
            rows.append((obj, cfg))
    remaining = [n for n in _nodes(export) if n.get("type") in RESOURCE_FIELD]
    issues: list[dict[str, str]] = []
    warnings: list[dict[str, str]] = []
    matched = []
    changed = 0
    for obj, cfg in rows:
        oid = str(obj.get("id"))
        node_type = NODE_TYPES.get(str(cfg.get("backend")))
        scale = _scale(cfg.get("scale"))
        if not node_type:
            issues.append({"id": oid, "error": f"unknown VFX backend {cfg.get('backend')!r}"})
            continue
        if scale is None:
            issues.append({"id": oid, "error": "VFX scale must be {x,y,z} numbers between 0.01 and 100"})
            continue
        path = str(cfg.get("resource_path") or "").lower()
        pos = ((obj.get("transform") or {}).get("position") or {})
        candidates = [(i, n) for i, n in enumerate(remaining)
                      if n.get("type") == node_type and _node_resource(n).lower() == path
                      and _distance(n.get("position") or {}, pos) <= MATCH_DISTANCE]
        if not candidates:
            warnings.append({"id": oid, "warning": f"no exported {node_type} for {cfg.get('resource_path')!r} at the saved position; "
                             "it is outside this export's scope or was moved without saving"})
            continue
        if len(candidates) > 1:
            issues.append({"id": oid, "error": f"{len(candidates)} exported {node_type} nodes share this resource and position; separate them before building"})
            continue
        index, node = candidates[0]
        remaining.pop(index)
        before = node.get("scale")
        if before != scale:
            changed += 1
            if write:
                node["scale"] = dict(scale)
        row = {"id": oid, "name": obj.get("name"), "node_type": node_type, "resource_path": cfg.get("resource_path"),
               "scale": scale, "export_scale": before}
        if node_type == "worldStaticParticleNode" and cfg.get("emission_rate") is not None:
            native = (node.get("data") or {}).get("emissionRate")
            row["emission_rate"] = cfg.get("emission_rate")
            row["export_emission_rate"] = native
            if native is None or abs(float(native) - float(cfg["emission_rate"])) > 1e-4:
                issues.append({"id": oid, "error": f"exported emissionRate {native!r} does not match authored {cfg['emission_rate']!r}; respawn the effect and export again"})
        matched.append(row)
    written = False
    if write and changed and not issues:
        export_path.write_text(json.dumps(export, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        written = True
    report = {"schema": "locationstudio-vfx-export/1", "export": str(export_path), "vfx_objects": len(rows),
              "matched": len(matched), "scale_changes": changed, "written": written, "ready": not issues,
              "matched_objects": matched, "issues": issues, "warnings": warnings,
              "note": "Scale is written to each matched node's world transform. Whether a given .particle/.effect visibly honors node scale must be checked in game."}
    if output is not None:
        target = Path(output)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        report["report_file"] = str(target)
    return report


def apply_to_workspace(project_file: str | Path, workspace: str | Path, output: str | Path | None = None) -> dict[str, Any]:
    """Patch the build workspace's raw export copy and record its new hash.

    The original World Builder export is left untouched; the converter reads
    the workspace copy named by the build manifest.
    """
    import hashlib

    from .build import load_manifest

    root, manifest = load_manifest(workspace)
    raw = root / str(manifest["exportFile"])
    report = apply(project_file, raw, write=True, output=output)
    if report["written"]:
        manifest["sourceExportSha256"] = manifest.get("sourceExportSha256") or manifest.get("exportSha256")
        manifest["exportSha256"] = hashlib.sha256(raw.read_bytes()).hexdigest()
        manifest["vfxScalePatched"] = report["scale_changes"]
        (root / ".cp77wb-build.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return report
