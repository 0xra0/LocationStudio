#!/usr/bin/env python3
"""VFX editor: native export scale patching and MCP argument contract."""
from __future__ import annotations

import hashlib
import json
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lsbuild import vfx  # noqa: E402

STEAM = "base\\fx\\environment\\steam\\steam_vent_small.particle"
HOLO = "base\\fx\\holo\\hologram_ad_flicker.effect"


def _particle_node(path: str, pos: dict, emission: float = 2.0) -> dict:
    return {"type": "worldStaticParticleNode", "position": {**pos, "w": 0}, "rotation": {"i": 0, "j": 0, "k": 0, "r": 1},
            "scale": {"x": 1, "y": 1, "z": 1},
            "data": {"emissionRate": emission, "forcedAutoHideDistance": -1, "forcedAutoHideRange": -1,
                     "particleSystem": {"DepotPath": {"$storage": "string", "$value": path}}}}


def _effect_node(path: str, pos: dict) -> dict:
    return {"type": "worldEffectNode", "position": {**pos, "w": 0}, "rotation": {"i": 0, "j": 0, "k": 0, "r": 1},
            "scale": {"x": 1, "y": 1, "z": 1},
            "data": {"streamingDistanceOverride": -1, "effect": {"DepotPath": {"$storage": "string", "$value": path}}}}


def _vfx_object(oid: str, backend: str, path: str, pos: dict, scale: dict, emission: float | None = None) -> dict:
    cfg = {"backend": backend, "resource_path": path, "scale": scale}
    if emission is not None:
        cfg["emission_rate"] = emission
    return {"id": oid, "name": oid, "transform": {"position": pos}, "metadata": {"vfx": cfg}}


def _fixture(root: Path, *, nodes: list[dict], objects: list[dict]) -> tuple[Path, Path]:
    project = root / "project.json"
    export = root / "demo_exported.json"
    project.write_text(json.dumps({"objects": objects}), encoding="utf-8")
    export.write_text(json.dumps({"name": "demo", "sectors": [{"name": "s", "nodes": nodes}]}), encoding="utf-8")
    return project, export


def test_scale_is_written_to_matching_nodes() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        pos_a, pos_b = {"x": 1, "y": 2, "z": 3}, {"x": 9, "y": 9, "z": 1}
        project, export = _fixture(Path(tmp),
            nodes=[_particle_node(STEAM, pos_a), _effect_node(HOLO, pos_b), {"type": "worldStaticMeshNode", "position": pos_a, "scale": {"x": 1, "y": 1, "z": 1}, "data": {}}],
            objects=[_vfx_object("steam", "particle", STEAM, {"x": 1.02, "y": 2, "z": 3}, {"x": 2, "y": 2, "z": 3}, 2.0),
                     _vfx_object("holo", "effect", HOLO.upper(), pos_b, {"x": 0.5, "y": 0.5, "z": 0.5}),
                     _vfx_object("elsewhere", "effect", HOLO, {"x": 90, "y": 0, "z": 0}, {"x": 1, "y": 1, "z": 1})])
        preview = vfx.apply(project, export)
        assert preview["ready"] and preview["matched"] == 2 and preview["scale_changes"] == 2 and not preview["written"]
        assert json.loads(export.read_text())["sectors"][0]["nodes"][0]["scale"]["x"] == 1, "preview must not write"
        assert preview["warnings"][0]["id"] == "elsewhere", "out-of-scope objects are warnings, not failures"
        report = vfx.apply(project, export, write=True)
        assert report["written"]
        nodes = json.loads(export.read_text())["sectors"][0]["nodes"]
        assert nodes[0]["scale"] == {"x": 2, "y": 2, "z": 3}
        assert nodes[1]["scale"] == {"x": 0.5, "y": 0.5, "z": 0.5}
        assert nodes[2]["scale"] == {"x": 1, "y": 1, "z": 1}, "non-VFX nodes are untouched"
        again = vfx.apply(project, export, write=True)
        assert again["scale_changes"] == 0 and not again["written"]


def test_emission_mismatch_and_ambiguity_block_build() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        pos = {"x": 0, "y": 0, "z": 0}
        project, export = _fixture(Path(tmp), nodes=[_particle_node(STEAM, pos, emission=1.0)],
                                   objects=[_vfx_object("steam", "particle", STEAM, pos, {"x": 1, "y": 1, "z": 1}, 4.0)])
        report = vfx.apply(project, export, write=True)
        assert not report["ready"] and "emissionRate" in report["issues"][0]["error"] and not report["written"]
    with tempfile.TemporaryDirectory() as tmp:
        pos = {"x": 0, "y": 0, "z": 0}
        project, export = _fixture(Path(tmp), nodes=[_effect_node(HOLO, pos), _effect_node(HOLO, pos)],
                                   objects=[_vfx_object("holo", "effect", HOLO, pos, {"x": 2, "y": 2, "z": 2})])
        report = vfx.apply(project, export)
        assert not report["ready"] and "share this resource" in report["issues"][0]["error"]
    with tempfile.TemporaryDirectory() as tmp:
        pos = {"x": 0, "y": 0, "z": 0}
        project, export = _fixture(Path(tmp), nodes=[_effect_node(HOLO, pos)],
                                   objects=[_vfx_object("holo", "effect", HOLO, pos, {"x": 0, "y": 1, "z": 1})])
        assert not vfx.apply(project, export)["ready"], "out-of-range scale must fail"


def test_workspace_copy_is_patched_and_manifest_rehashed() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        pos = {"x": 1, "y": 1, "z": 1}
        project, export = _fixture(root, nodes=[_effect_node(HOLO, pos)],
                                   objects=[_vfx_object("holo", "effect", HOLO, pos, {"x": 3, "y": 3, "z": 3})])
        workspace = root / "ws"
        raw = workspace / "source" / "raw" / export.name
        raw.parent.mkdir(parents=True)
        raw.write_bytes(export.read_bytes())
        original = hashlib.sha256(raw.read_bytes()).hexdigest()
        from lsbuild.build import MANIFEST_SCHEMA
        (workspace / ".cp77wb-build.json").write_text(json.dumps({"schema": MANIFEST_SCHEMA, "exportFile": f"source/raw/{export.name}", "exportSha256": original}), encoding="utf-8")
        report = vfx.apply_to_workspace(project, workspace, workspace / "automation" / "vfx-export.json")
        assert report["written"] and Path(report["report_file"]).is_file()
        manifest = json.loads((workspace / ".cp77wb-build.json").read_text())
        assert manifest["sourceExportSha256"] == original
        assert manifest["exportSha256"] == hashlib.sha256(raw.read_bytes()).hexdigest() != original
        assert json.loads(export.read_text())["sectors"][0]["nodes"][0]["scale"]["x"] == 1, "the original WB export is not modified"


def test_mcp_tools_send_expected_payloads() -> None:
    try:
        import server
    except ModuleNotFoundError as exc:  # the mcp package is optional for offline checks
        print(f"SKIP MCP payload test: {exc}")
        return
    sent: list[tuple[str, dict]] = []
    saved = server._send
    server._send = lambda op, args=None: sent.append((op, args or {})) or {"ok": True}
    try:
        server.vfx_search(query="steam", category="steam")
        server.vfx_create(resource_path=STEAM, yaw=90, scale=2, emission_rate=3, align_to_surface=True)
        server.vfx_create(query="holo", source="player", scale_x=1, scale_y=2, scale_z=3)
        server.vfx_update("obj1", pitch=10, scale=1.5)
        server.vfx_preview(query="fire", follow=False)
        server.vfx_preview(update=True, yaw=45)
        server.vfx_preview_commit(name="Fire", scale=2)
        server.vfx_preview_clear()
        for bad in (lambda: server.vfx_create(scale_x=1), lambda: server.vfx_create(source="sky"),
                    lambda: server.vfx_search(backend="mesh"), lambda: server.vfx_create(x=1)):
            try:
                bad()
            except ValueError:
                pass
            else:
                raise AssertionError("invalid MCP arguments must be rejected before sending")
    finally:
        server._send = saved
    ops = [op for op, _ in sent]
    assert ops == ["vfx_search", "vfx_create", "vfx_create", "vfx_update", "vfx_preview", "vfx_preview", "vfx_preview_commit", "vfx_preview_clear"], ops
    create = sent[1][1]
    assert create["resource_path"] == STEAM and create["yaw"] == 90 and create["scale"] == 2 and create["align_to_surface"] is True
    assert "roll" not in create, "unset rotation axes must not override surface alignment"
    assert sent[2][1]["scale"] == {"x": 1, "y": 2, "z": 3} and sent[2][1]["source"] == "player"
    assert sent[3][1] == {"object_id": "obj1", "patch": {"pitch": 10, "scale": 1.5}}
    assert sent[4][1]["follow"] is False and sent[5][1]["update"] is True
    assert not {"follow", "align_to_surface", "distance"} & set(sent[5][1]), "preview updates must not reset unspecified settings"
    assert sent[6][1]["scale"] == 2


if __name__ == "__main__":
    test_scale_is_written_to_matching_nodes()
    test_emission_mismatch_and_ambiguity_block_build()
    test_workspace_copy_is_patched_and_manifest_rehashed()
    test_mcp_tools_send_expected_payloads()
    print("PASS VFX export and MCP contract")
