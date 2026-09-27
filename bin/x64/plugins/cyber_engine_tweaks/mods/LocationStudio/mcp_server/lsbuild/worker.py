from __future__ import annotations

import hashlib
import json
import os
import platform
import shutil
import subprocess
import sys
import tempfile
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .native import required_template_types, prepare_native_json, verify_native_outputs, TEMPLATE_SCHEMA

WORKER_PROTOCOL = "cp77wb-wkit-worker/1"
DEFAULT_WORKER_NAME = "cp77wb-wkit-worker"
LOCAL_PUBLISH_DIR = Path(__file__).resolve().parent / "wkit_worker" / "publish"


def _resolve_worker(worker: str | Path | None = None) -> str | None:
    if worker:
        p = Path(str(worker)).expanduser()
        if p.exists():
            return str(p.resolve())
        found = shutil.which(str(worker))
        if found:
            return found
    env = os.environ.get("CP77WB_WKIT_WORKER")
    if env:
        p = Path(env).expanduser()
        if p.exists():
            return str(p.resolve())
        found = shutil.which(env)
        if found:
            return found
    found = shutil.which(DEFAULT_WORKER_NAME)
    if found:
        return found
    # LocationStudio: the default `build_worker` output directory.
    for name in (DEFAULT_WORKER_NAME, DEFAULT_WORKER_NAME + ".exe"):
        if (LOCAL_PUBLISH_DIR / name).is_file():
            return str(LOCAL_PUBLISH_DIR / name)
    return None



def _file_info(path: str | Path | None) -> dict[str, Any] | None:
    if not path:
        return None
    p = Path(path)
    if not p.is_file():
        return {"path": str(p), "exists": False}
    h = hashlib.sha256()
    with p.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    st = p.stat()
    return {"path": str(p.resolve()), "exists": True, "size": st.st_size, "sha256": h.hexdigest()}


def _capture_command(cmd: list[str], *, timeout: int = 30) -> dict[str, Any]:
    try:
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                              timeout=timeout, check=False)
        return {"command": cmd, "exitCode": proc.returncode, "output": proc.stdout or ""}
    except Exception as exc:
        return {"command": cmd, "error": str(exc), "exitCode": None, "output": ""}


def worker_inspect(*, worker: str | Path | None = None, timeout: int = 30) -> dict[str, Any]:
    """Return reflection/API discovery from the worker without requiring its CR2W round-trip to pass."""
    path = _resolve_worker(worker)
    result: dict[str, Any] = {
        "protocol": WORKER_PROTOCOL, "worker": path, "found": bool(path), "inspectAvailable": False
    }
    if not path:
        result["reason"] = "cp77wb-wkit-worker not found"
        return result
    result["workerFile"] = _file_info(path)
    cap = _capture_command([path, "inspect", "--json"], timeout=timeout)
    result["exitCode"] = cap.get("exitCode")
    result["raw"] = cap.get("output", "")[-20000:]
    if cap.get("exitCode") != 0:
        result["reason"] = "worker inspect command failed"
        return result
    try:
        data = json.loads(cap.get("output") or "{}")
    except json.JSONDecodeError as exc:
        result["reason"] = f"worker inspect returned invalid JSON: {exc}"
        return result
    if not isinstance(data, dict):
        result["reason"] = "worker inspect returned non-object JSON"
        return result
    if data.get("protocol") != WORKER_PROTOCOL:
        result["reason"] = f"worker protocol mismatch: {data.get('protocol')!r}"
        result["inspect"] = data
        return result
    result["inspect"] = data
    result["apiProfile"] = data.get("apiProfile")
    result["inspectAvailable"] = True
    return result


def worker_doctor(*, worker: str | Path | None = None, dotnet: str | Path | None = None,
                  output: str | Path | None = None, timeout: int = 30) -> dict[str, Any]:
    """Collect reproducible worker/.NET/WolvenKit diagnostics for a later compatibility test."""
    worker_path = _resolve_worker(worker)
    dn = str(dotnet) if dotnet else shutil.which("dotnet")
    source_dir = Path(__file__).resolve().parent / "wkit_worker"
    report: dict[str, Any] = {
        "schema": "cp77wb-worker-doctor/1",
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "cp77wbVersion": __import__("cp77wb").__version__,
        "protocol": WORKER_PROTOCOL,
        "platform": {
            "python": sys.version, "implementation": platform.python_implementation(),
            "system": platform.system(), "release": platform.release(), "machine": platform.machine(),
            "platform": platform.platform(),
        },
        "worker": worker_path,
        "workerFile": _file_info(worker_path),
        "dotnet": dn,
        "source": {
            "project": _file_info(source_dir / "cp77wb-wkit-worker.csproj"),
            "program": _file_info(source_dir / "Program.cs"),
        },
    }
    dotnet_commands: dict[str, Any] = {}
    if dn:
        for name, args in {
            "info": [dn, "--info"],
            "sdks": [dn, "--list-sdks"],
            "runtimes": [dn, "--list-runtimes"],
        }.items():
            dotnet_commands[name] = _capture_command([str(x) for x in args], timeout=timeout)
    else:
        dotnet_commands["reason"] = "dotnet not found"
    report["dotnetDiagnostics"] = dotnet_commands
    report["inspect"] = worker_inspect(worker=worker_path, timeout=timeout) if worker_path else {"found": False}
    report["preflight"] = worker_preflight(worker=worker_path, timeout=timeout) if worker_path else {"found": False, "ready": False}
    report["ready"] = bool(report.get("preflight", {}).get("ready"))

    if output:
        out = Path(output).expanduser().resolve()
        if out.suffix.lower() != ".zip":
            out = out / "cp77wb-worker-doctor.zip"
        out.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="cp77wb-worker-doctor-") as td:
            td_path = Path(td)
            (td_path / "diagnostics.json").write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
            for name, entry in dotnet_commands.items():
                if isinstance(entry, dict) and entry.get("output"):
                    (td_path / f"dotnet-{name}.txt").write_text(entry["output"], encoding="utf-8")
            for name in ("Program.cs", "cp77wb-wkit-worker.csproj", "README.md", "build.sh"):
                src = source_dir / name
                if src.is_file():
                    shutil.copy2(src, td_path / name)
            with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED) as zf:
                for f in sorted(td_path.iterdir()):
                    zf.write(f, arcname=f.name)
        report["supportBundle"] = str(out)
        report["supportBundleFile"] = _file_info(out)
    return report

def worker_preflight(*, worker: str | Path | None = None, timeout: int = 30) -> dict[str, Any]:
    path = _resolve_worker(worker)
    result: dict[str, Any] = {
        "protocol": WORKER_PROTOCOL,
        "worker": path,
        "found": bool(path),
        "ready": False,
        "authoritativeNative": False,
        "capabilities": {"createTemplates": False, "jsonToCr2w": False},
    }
    if not path:
        result["reason"] = "cp77wb-wkit-worker not found; run build_worker(run=True) or set CP77WB_WKIT_WORKER"
        return result
    try:
        proc = subprocess.run([path, "selftest", "--json"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                              text=True, timeout=timeout, check=False)
        result["exitCode"] = proc.returncode
        result["raw"] = (proc.stdout or "")[-8000:]
        if proc.returncode != 0:
            result["reason"] = "worker selftest failed"
            return result
        data = json.loads(proc.stdout)
        if not isinstance(data, dict):
            raise ValueError("worker selftest returned non-object JSON")
        result["selftest"] = data
        if data.get("protocol") != WORKER_PROTOCOL:
            result["reason"] = f"worker protocol mismatch: {data.get('protocol')!r}"
            return result
        caps = data.get("capabilities") or {}
        create_ok = bool(caps.get("createTemplates"))
        cr2w_ok = bool(caps.get("jsonToCr2w"))
        result["capabilities"] = {"createTemplates": create_ok, "jsonToCr2w": cr2w_ok}
        result["wolvenKitVersion"] = data.get("wolvenKitVersion")
        result["dotnetVersion"] = data.get("dotnetVersion")
        result["apiProfile"] = data.get("apiProfile")
        result["ready"] = create_ok and cr2w_ok
        result["authoritativeNative"] = result["ready"]
        if not result["ready"]:
            result["reason"] = data.get("reason") or "worker did not verify both required capabilities"
    except Exception as exc:
        result["reason"] = str(exc)
    return result


def _run_json(cmd: list[str], *, timeout: int) -> dict[str, Any]:
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=timeout, check=False)
    if proc.returncode != 0:
        raise RuntimeError(f"Worker failed ({proc.returncode}): {' '.join(cmd)}\n{proc.stdout[-8000:]}")
    try:
        data = json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Worker returned invalid JSON: {proc.stdout[-8000:]}") from exc
    if not isinstance(data, dict):
        raise RuntimeError("Worker returned non-object JSON")
    return data


def worker_create_bundle(export_file: str | Path, output: str | Path, *, worker: str | Path | None = None,
                         run: bool = False, timeout: int = 120) -> dict[str, Any]:
    pf = worker_preflight(worker=worker, timeout=min(timeout, 30))
    types = required_template_types(export_file)
    plan = {"worker": pf.get("worker"), "output": str(Path(output).resolve()), "types": types, "count": len(types),
            "run": bool(run), "ready": bool(pf.get("ready")), "preflight": pf}
    if not pf.get("ready"):
        return plan
    if not run:
        return plan
    with tempfile.TemporaryDirectory(prefix="cp77wb-worker-types-") as td:
        types_file = Path(td) / "types.json"
        types_file.write_text(json.dumps(types, ensure_ascii=False), encoding="utf-8")
        out = Path(output).resolve()
        out.parent.mkdir(parents=True, exist_ok=True)
        data = _run_json([str(pf["worker"]), "templates", "--types", str(types_file), "--output", str(out), "--json"], timeout=timeout)
        if not out.is_file():
            raise RuntimeError(f"Worker reported success but did not create {out}")
        bundle = json.loads(out.read_text(encoding="utf-8-sig"))
        if bundle.get("schema") != TEMPLATE_SCHEMA or not isinstance(bundle.get("types"), dict):
            raise RuntimeError("Worker output is not a cp77wb template bundle")
        missing = [t for t in types if t not in bundle["types"]]
        if missing:
            raise RuntimeError(f"Worker template bundle missing required types: {missing}")
        plan.update({"created": True, "workerResult": data, "bundle": str(out), "missing": []})
    return plan


def worker_convert(native_json: str | Path, output: str | Path, *, worker: str | Path | None = None,
                   run: bool = False, timeout: int = 300) -> dict[str, Any]:
    native_root = Path(native_json).resolve()
    manifest_path = native_root / ".cp77wb-native-json.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    pf = worker_preflight(worker=worker, timeout=min(timeout, 30))
    actions = []
    out_root = Path(output).resolve()
    for item in manifest.get("files", []):
        src = Path(item["json"])
        target = out_root / item["target"]
        actions.append({"json": str(src), "target": str(target), "run": bool(run)})
    result: dict[str, Any] = {"run": bool(run), "ready": bool(pf.get("ready")), "preflight": pf, "actions": actions,
                              "output": str(out_root)}
    if not pf.get("ready") or not run:
        return result
    for action in actions:
        target = Path(action["target"])
        target.parent.mkdir(parents=True, exist_ok=True)
        data = _run_json([str(pf["worker"]), "deserialize", "--input", action["json"], "--output", str(target), "--json"], timeout=timeout)
        action["workerResult"] = data
        if not target.is_file():
            raise RuntimeError(f"Worker did not create {target}")
        if target.read_bytes()[:4] != b"CR2W":
            raise RuntimeError(f"Worker output {target} does not begin with CR2W magic")
    targets = [item["target"] for item in manifest.get("files", [])]
    verify = verify_native_outputs(out_root, targets, strict_magic=True)
    result["verification"] = verify
    result["native"] = bool(verify.get("valid"))
    return result


def worker_import(export_file: str | Path, output: str | Path, *, worker: str | Path | None = None,
                  run: bool = False, keep_json: bool = True, timeout: int = 300) -> dict[str, Any]:
    output = Path(output).resolve()
    bundle = output.parent / (output.name + ".cp77wb-worker-templates.json")
    json_root = output.parent / (output.name + ".cp77wb-worker-json")
    bundle_result = worker_create_bundle(export_file, bundle, worker=worker, run=run, timeout=timeout)
    result: dict[str, Any] = {"run": bool(run), "bundle": bundle_result, "output": str(output), "native": False}
    if not bundle_result.get("ready") or not run:
        result["ready"] = bool(bundle_result.get("ready"))
        return result
    prep = prepare_native_json(export_file, bundle, json_root)
    conv = worker_convert(json_root, output, worker=worker, run=True, timeout=timeout)
    result.update({"ready": bool(conv.get("ready")), "prepared": prep, "conversion": conv,
                   "native": bool(conv.get("verification", {}).get("valid")), "authoritativeNative": bool(conv.get("verification", {}).get("valid"))})
    if result["native"] and not keep_json:
        shutil.rmtree(json_root, ignore_errors=True)
    return result


def build_worker(*, source: str | Path | None = None, output: str | Path | None = None, dotnet: str | Path | None = None,
                 run: bool = False, timeout: int = 600, log_file: str | Path | None = None) -> dict[str, Any]:
    if source is None:
        source = Path(__file__).resolve().parent / "wkit_worker" / "cp77wb-wkit-worker.csproj"
    source = Path(source).resolve()
    if output is None:
        output = source.parent / "publish"
    output = Path(output).resolve()
    dn = str(dotnet) if dotnet else shutil.which("dotnet")
    result: dict[str, Any] = {"source": str(source), "output": str(output), "dotnet": dn, "run": bool(run), "ready": bool(dn and source.is_file())}
    if not result["ready"]:
        result["reason"] = "dotnet not found" if not dn else f"worker project not found: {source}"
        return result
    cmd = [str(dn), "publish", str(source), "-c", "Release", "-o", str(output)]
    result["command"] = cmd
    if not run:
        return result
    output.mkdir(parents=True, exist_ok=True)
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=timeout, check=False)
    result.update({"exitCode": proc.returncode, "log": proc.stdout[-12000:]})
    if log_file:
        lp = Path(log_file).expanduser().resolve()
        lp.parent.mkdir(parents=True, exist_ok=True)
        lp.write_text(proc.stdout or "", encoding="utf-8")
        result["logFile"] = str(lp)
    if proc.returncode != 0:
        result["ready"] = False
        result["reason"] = "dotnet publish failed"
        return result
    candidates = [output / DEFAULT_WORKER_NAME, output / (DEFAULT_WORKER_NAME + ".exe")]
    worker_path = next((p for p in candidates if p.is_file()), None)
    result["worker"] = str(worker_path) if worker_path else None
    if not worker_path:
        result["ready"] = False
        result["reason"] = "publish succeeded but worker executable was not found"
        return result
    result["preflight"] = worker_preflight(worker=worker_path, timeout=30)
    result["ready"] = bool(result["preflight"].get("ready"))
    return result
