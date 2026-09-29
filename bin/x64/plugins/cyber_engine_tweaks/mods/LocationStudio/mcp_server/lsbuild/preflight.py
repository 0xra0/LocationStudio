"""Shipping preflight: offline checks and the merge with the in-game checks.

The in-game half (modules/preflight.lua, bridge op ``preflight_run``) checks
the project and live runtime. This module turns the offline reports into the
same check format (dependencies, sector report, native interactables, NPC
population audit, visual regression) and merges everything into one report
with a single verdict. When the game is not running the in-game checks are
reported as skipped and the report is never ``ready``.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

SCHEMA = "locationstudio-preflight/1"
MAX_ISSUES = 200

LIVE_CHECKS = (
    ("project", "Project data"), ("resource_paths", "Resource paths"), ("bounds", "Asset bounds"), ("generated_bounds", "Generated bounds"), ("spawns", "Spawns"),
    ("noderefs", "NodeRefs"), ("quest_facts", "Quest facts"), ("interactables", "Native interactable setup"),
    ("ambient_areas", "Ambient areas"), ("workspots", "Workspots and routes"), ("device_links", "Device links"),
    ("cet_entities", "Exportable objects"),
)


class Check(dict):
    def __init__(self, cid: str, label: str):
        super().__init__(id=cid, label=label, status="pass", issues=[])

    def add(self, severity: str, message: str, **extra: Any) -> "Check":
        if len(self["issues"]) < MAX_ISSUES:
            self["issues"].append({"severity": severity, "message": message, **{k: v for k, v in extra.items() if v is not None}})
        else:
            self["truncated"] = True
        if severity == "error":
            self["status"] = "fail"
        elif severity == "warning" and self["status"] == "pass":
            self["status"] = "warn"
        return self

    def skip(self, note: str) -> "Check":
        self["status"] = "skipped"
        self["note"] = note
        return self


def dependencies_check(report: dict[str, Any] | None, error: str | None = None) -> Check:
    c = Check("dependencies", "Asset dependencies")
    if report is None:
        return c.skip(error or "dependency scan did not run")
    for m in report.get("missing", []):
        chain = " → ".join(str(x) for x in (m.get("chain") or [])) or m.get("path")
        c.add("error", f"missing {m.get('path')} ({chain})", path=m.get("path"),
              object_id=str((m.get("chain") or [""])[0]).replace("object:", "") or None)
    for p in report.get("raw_json_only", []):
        c.add("error", f"{p} exists only as WolvenKit raw JSON; convert it before packing", path=p)
    for archive, paths in (report.get("external_requirements") or {}).items():
        c.add("warning", f"requires the installed mod {archive} ({len(paths)} file(s)); players need it too", archive=archive)
    unknown = report.get("unknown", [])
    if unknown:
        c.add("warning", f"{len(unknown)} file(s) could not be classified; run dependency_index_build")
    unverified = report.get("unverified", [])
    if unverified:
        c.add("info", f"{len(unverified)} TweakDB record(s)/audio event(s) assumed vanilla (not indexed)")
    if report.get("warning"):
        c["note"] = report["warning"]
    return c


def _ref_root(ref: str) -> str:
    parts = [p for p in str(ref).split("/") if p]
    return "/".join(parts[:2])


def sectors_check(report: dict[str, Any] | None, error: str | None = None) -> tuple[Check, list[dict[str, Any]], list[dict[str, Any]]]:
    """Sector check plus NodeRef and device-link issues from the same report."""
    c = Check("sectors", "Streaming sectors")
    noderef_issues: list[dict[str, Any]] = []
    device_issues: list[dict[str, Any]] = []
    if report is None:
        return c.skip(error or "no World Builder export to inspect; run Build Mod or build_export_world_builder first"), [], []
    for f in report.get("flags", []):
        sev = f.get("severity")
        if sev in ("error", "warning"):
            where = f.get("sector") or "export"
            c.add(sev, f"{where}: {f.get('message')}", code=f.get("code"), object_id=f.get("object_id"), node=f.get("node_name"))
    own_roots = {_ref_root(n.get("node_ref")) for n in report.get("nodes", []) if n.get("node_ref")}
    own_roots |= {_ref_root(r.get("from_node_ref")) for r in report.get("cross_sector_references", []) if r.get("from_node_ref")}
    own_roots.discard("")
    for r in report.get("cross_sector_references", []):
        if r.get("status") == "external_or_missing":
            ref = str(r.get("target_ref"))
            ours = _ref_root(ref) in own_roots
            noderef_issues.append({"severity": "error" if ours else "warning",
                                   "message": f"{r.get('from_node') or r.get('from_sector')} references {ref}, which is "
                                              + ("not in this export" if ours else "outside this export (vanilla or another mod; not verifiable)"),
                                   "node_ref": ref})
        elif r.get("status") == "missing_device":
            device_issues.append({"severity": "error", "message": f"device {r.get('from_device')} links to device {r.get('to_device')}, which is not in the export"})
    return c, noderef_issues, device_issues


def interactables_check(result: dict[str, Any] | None, error: str | None = None) -> Check:
    c = Check("native_interactables", "Native interactable artifacts")
    if result is None:
        return c.skip(error or "no export to generate native interactables from")
    for i in result.get("issues", []):
        c.add("error", f"{i.get('object')}: {i.get('error')}", object_id=i.get("object") or None)
    if result.get("interactables") and not result.get("native_export", {}).get("nodes"):
        c.add("error", "interactables exist but the export has no nodes")
    return c


def population_check(audit: dict[str, Any] | None, error: str | None = None) -> Check:
    c = Check("npc_population", "NPC population export")
    if audit is None:
        return c.skip(error or "no export to audit")
    for i in audit.get("issues", []):
        c.add("error", str(i.get("error")), object_id=i.get("id"))
    return c


def visual_check(regression_dir: Path, *, project_updated_at: str | None = None, capture: dict[str, Any] | None = None) -> Check:
    c = Check("visual_regression", "Visual regression")
    manifest = capture
    if manifest is None:
        runs = sorted((regression_dir / "runs").glob("*/manifest.json")) if (regression_dir / "runs").is_dir() else []
        if not runs:
            return c.skip("no visual-regression run yet; run visual_regression_capture (or preflight with run_visual_regression)")
        try:
            manifest = json.loads(runs[-1].read_text(encoding="utf-8"))
        except (OSError, ValueError) as exc:
            return c.add("warning", f"latest run manifest is unreadable: {exc}")
    status = manifest.get("status")
    run = manifest.get("run_id")
    if status == "regression":
        for cam in manifest.get("cameras", []):
            if cam.get("regression") is True:
                m = cam.get("comparison") or {}
                what = ("is not comparable with the baseline (size changed)" if m.get("compatible") is False else
                        f"changed {float(m.get('changed_fraction', 0)) * 100:.1f}% against the accepted baseline")
                c.add("error", f"camera {cam.get('name') or cam.get('camera_id')} {what}", camera_id=cam.get("camera_id"), run_id=run)
        if c["status"] != "fail":
            c.add("error", f"run {run} reports a regression", run_id=run)
    elif status == "passed":
        pass
    elif status == "captured":
        c.add("warning", f"run {run} has no accepted baseline to compare with; review it and visual_regression_accept", run_id=run)
    else:
        c.add("warning", f"run {run} is {status or 'incomplete'}", run_id=run)
    if manifest.get("environment_mismatch"):
        c.add("warning", "baseline was captured under a different environment; the comparison is not reliable", run_id=run)
    created = str(manifest.get("created_at") or "")
    if project_updated_at and created and created[:19] < str(project_updated_at)[:19]:
        c.add("warning", "the project changed after the latest visual-regression run; capture again", run_id=run)
    c["run_id"] = run
    return c


def _summarize(checks: list[dict[str, Any]]) -> dict[str, int]:
    s = {"pass": 0, "warn": 0, "fail": 0, "skipped": 0, "errors": 0, "warnings": 0}
    for c in checks:
        c["count"] = len(c.get("issues", []))
        s[c["status"]] = s.get(c["status"], 0) + 1
        for i in c.get("issues", []):
            if i.get("severity") == "error":
                s["errors"] += 1
            elif i.get("severity") == "warning":
                s["warnings"] += 1
    return s


def merge(live: dict[str, Any] | None, offline: list[Check], *, live_error: str | None = None,
          noderef_issues: list[dict[str, Any]] | None = None, device_issues: list[dict[str, Any]] | None = None,
          strict: bool = False, scope: dict[str, Any] | None = None) -> dict[str, Any]:
    checks: list[dict[str, Any]] = []
    if live and isinstance(live.get("checks"), list):
        checks.extend(dict(c) for c in live["checks"])
    else:
        for cid, label in LIVE_CHECKS:
            checks.append(Check(cid, label).skip(f"game not running or LocationStudio not ready: {live_error or 'no live report'}"))
    by_id = {c["id"]: c for c in checks}

    def extend(cid: str, label: str, issues: list[dict[str, Any]]) -> None:
        if not issues:
            return
        c = by_id.get(cid)
        if c is None:
            c = Check(cid, label)
            checks.append(c)
            by_id[cid] = c
        c.setdefault("issues", [])
        for i in issues:
            c["issues"].append(i)
            if i["severity"] == "error":
                c["status"] = "fail"
            elif i["severity"] == "warning" and c["status"] in ("pass", "skipped"):
                c["status"] = "warn"

    extend("noderefs", "NodeRefs", noderef_issues or [])
    extend("device_links", "Device links", device_issues or [])
    checks.extend(offline)
    summary = _summarize(checks)
    live_ok = bool(live and live.get("checks"))
    ready = summary["fail"] == 0 and live_ok and (not strict or summary["warn"] == 0)
    blocking = [{"check": c["id"], "label": c["label"], "errors": sum(1 for i in c.get("issues", []) if i.get("severity") == "error")}
                for c in checks if c["status"] == "fail"]
    return {"schema": SCHEMA, "source": "mcp", "ready": ready, "strict": strict, "live": live_ok,
            "live_error": None if live_ok else live_error, "scope": scope or {}, "summary": summary,
            "blocking": blocking, "checks": checks,
            "note": None if live_ok else "In-game checks were skipped; start the game with LocationStudio loaded and run again before shipping."}
