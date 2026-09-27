from __future__ import annotations

import hashlib
import json
import re
import sqlite3
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Iterator

from .errors import Cp77wbError


@dataclass(frozen=True)
class AssetSourceSpec:
    rel_dir: str
    category: str
    variant: str
    module_path: str
    data_type: str
    source_kind: str = "list"  # list = *.txt entries, template = *.json files


# This table is intentionally explicit. It mirrors modules/ui/spawnUI.lua and the
# spawnDataPath/modulePath values in modules/classes/spawn/* from World Builder.
# If an upstream release adds a source that is not listed here, the generic
# scanner still indexes JSON templates and reports unclassified TXT lists.
ASSET_SOURCE_SPECS: tuple[AssetSourceSpec, ...] = (
    AssetSourceSpec("entity/templates", "Entity", "Template", "entity/entityTemplate", "Entity Template"),
    AssetSourceSpec("entity/device", "Entity", "Device", "entity/device", "Device"),
    AssetSourceSpec("entity/records", "Entity", "Record", "entity/entityRecord", "Entity Record"),
    AssetSourceSpec("ai/aiSpot", "AI", "AI Spot", "ai/aiSpot", "AI Spot"),
    AssetSourceSpec("mesh/all", "Mesh", "Mesh", "mesh/mesh", "Static Mesh"),
    AssetSourceSpec("mesh/all", "Mesh", "Rotating Mesh", "mesh/rotatingMesh", "Rotating Mesh"),
    AssetSourceSpec("mesh/all", "Mesh", "Proxy Mesh", "mesh/proxyMesh", "Proxy Mesh"),
    AssetSourceSpec("mesh/cloth", "Mesh", "Cloth Mesh", "mesh/clothMesh", "Cloth Mesh"),
    AssetSourceSpec("mesh/physics", "Mesh", "Dynamic Mesh", "physics/dynamicMesh", "Dynamic Mesh"),
    AssetSourceSpec("colliders", "Collision", "Collision Mesh", "collision/meshCollider", "Collision Mesh"),
    AssetSourceSpec("meta/reflectionProbe", "Lighting", "Reflection Probe", "meta/reflectionProbe", "Reflection Probe"),
    AssetSourceSpec("visual/particles", "Deco", "Particles", "visual/particle", "Particles"),
    AssetSourceSpec("visual/decals", "Deco", "Decals", "visual/decal", "Decals"),
    AssetSourceSpec("visual/effects", "Deco", "Effects", "visual/effect", "Effects"),
    AssetSourceSpec("visual/sounds", "Deco", "Static Audio Emitter", "visual/audio", "Sounds"),
)

# JSON template directories. module_path/data_type normally come from the JSON
# itself, so these values are fallback metadata only.
TEMPLATE_DIR_HINTS: dict[str, tuple[str, str]] = {
    "lights/staticLights": ("Lighting", "Static Light"),
    "lights/lightChannelArea": ("Lighting", "Light Channel Area"),
    "visual/fog": ("Lighting", "Fog Volume"),
    "visual/waterPatch": ("Deco", "Water Patch"),
    "colliders": ("Collision", "Collision Shape"),
    "meta/occluder": ("Meta", "Occluder"),
    "meta/staticMarker": ("Meta", "Static Marker"),
    "meta/splineMarker": ("Meta", "Spline Point"),
    "meta/spline": ("Meta", "Spline"),
    "area/outlineMarker": ("Area", "Outline Marker"),
    "area/kill": ("Area", "Kill Area"),
    "area/preventionFree": ("Area", "Prevention Free"),
    "area/waterNull": ("Area", "Water Null"),
    "area/triggerArea": ("Area", "Trigger Area"),
    "area/ambientArea": ("Area", "Ambient Area"),
    "area/dummy": ("Area", "Dummy Area"),
    "area/conversationArea": ("Area", "Conversation Area"),
    "area/crowdNull": ("Area", "Crowd Null Area"),
    "area/guardArea": ("Area", "Guard Area"),
    "ai/community": ("AI", "Community"),
    "entity/amm": ("Entity", "Template (AMM)"),
}


@dataclass(frozen=True)
class AssetRecord:
    category: str
    variant: str
    module_path: str
    data_type: str
    name: str
    file_name: str
    spawn_data: str
    extension: str
    source_file: str
    source_kind: str
    template_json: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass(frozen=True)
class AssetSearchResult:
    id: int
    category: str
    variant: str
    module_path: str
    data_type: str
    name: str
    file_name: str
    spawn_data: str
    extension: str
    source_file: str
    source_kind: str
    template: dict[str, Any] | None
    rank: float | None = None

    def to_dict(self) -> dict[str, Any]:
        out = asdict(self)
        out["template"] = self.template
        return out


class AssetCatalogError(Cp77wbError):
    pass


def find_worldbuilder_root(path: str | Path) -> Path:
    """Find a World Builder root containing data/spawnables.

    Accepts the installed entSpawner directory, the project source root, or an
    extracted GitHub archive with one nested project directory.
    """
    p = Path(path).expanduser().resolve()
    candidates = [p]
    if p.is_dir():
        candidates.extend(child for child in p.iterdir() if child.is_dir())
    for candidate in candidates:
        if (candidate / "data" / "spawnables").is_dir():
            return candidate
    raise AssetCatalogError(f"Could not find data/spawnables under {p}")


def default_catalog_path(world_builder_root: str | Path) -> Path:
    root = find_worldbuilder_root(world_builder_root)
    return root / ".cp77wb" / "assets.sqlite3"


def _file_name(value: str) -> str:
    normalized = value.replace("/", "\\")
    part = normalized.rsplit("\\", 1)[-1]
    return part


def _extension(value: str) -> str:
    name = _file_name(value)
    if "." not in name:
        return ""
    return "." + name.rsplit(".", 1)[-1].lower()


def _safe_json_load(path: Path) -> dict[str, Any] | None:
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError, UnicodeDecodeError):
        return None
    return data if isinstance(data, dict) else None


def _iter_list_records(root: Path, spec: AssetSourceSpec) -> Iterator[AssetRecord]:
    directory = root / "data" / "spawnables" / spec.rel_dir
    if not directory.is_dir():
        return
    seen: set[str] = set()
    for txt in sorted(directory.rglob("*.txt")):
        try:
            lines = txt.read_text(encoding="utf-8-sig", errors="replace").splitlines()
        except OSError:
            continue
        for raw in lines:
            value = raw.strip()
            if not value or value in seen:
                continue
            seen.add(value)
            name = value
            file_name = _file_name(value)
            yield AssetRecord(
                category=spec.category,
                variant=spec.variant,
                module_path=spec.module_path,
                data_type=spec.data_type,
                name=name,
                file_name=file_name,
                spawn_data=value,
                extension=_extension(value),
                source_file=str(txt.relative_to(root)),
                source_kind="list",
            )


def _dir_hint(rel_parent: str) -> tuple[str, str]:
    rel_parent = rel_parent.replace("\\", "/")
    # Longest-prefix wins; this lets entity/amm/subfolders work.
    matches = [(key, value) for key, value in TEMPLATE_DIR_HINTS.items() if rel_parent == key or rel_parent.startswith(key + "/")]
    if matches:
        return max(matches, key=lambda item: len(item[0]))[1]
    top = rel_parent.split("/", 1)[0].title() if rel_parent else "Other"
    return top, "Template"


def _iter_template_records(root: Path) -> Iterator[AssetRecord]:
    spawn_root = root / "data" / "spawnables"
    for path in sorted(spawn_root.rglob("*.json")):
        data = _safe_json_load(path)
        if not data:
            continue
        spawn = data.get("spawnable") if isinstance(data.get("spawnable"), dict) else None
        if spawn is None:
            # Some custom generated files are full spawnableElement serializations.
            if data.get("modulePath") == "modules/classes/editor/spawnableElement" and isinstance(data.get("spawnable"), dict):
                spawn = data["spawnable"]
            else:
                continue
        rel_parent = str(path.parent.relative_to(spawn_root)).replace("\\", "/")
        category, variant = _dir_hint(rel_parent)
        module_path = str(spawn.get("modulePath", ""))
        data_type = str(spawn.get("dataType", variant))
        spawn_data = str(spawn.get("spawnData", ""))
        name = str(data.get("name", path.stem))
        file_name = _file_name(spawn_data) if spawn_data else name
        # Store only the spawnable payload. That is exactly what spawnUI loads
        # from JSON template files through config.loadFiles().
        yield AssetRecord(
            category=category,
            variant=variant,
            module_path=module_path,
            data_type=data_type,
            name=name,
            file_name=file_name,
            spawn_data=spawn_data,
            extension=_extension(spawn_data),
            source_file=str(path.relative_to(root)),
            source_kind="template",
            template_json=json.dumps(spawn, ensure_ascii=False, separators=(",", ":")),
        )


def iter_asset_records(world_builder_root: str | Path) -> Iterator[AssetRecord]:
    root = find_worldbuilder_root(world_builder_root)
    for spec in ASSET_SOURCE_SPECS:
        yield from _iter_list_records(root, spec)
    yield from _iter_template_records(root)


def _source_fingerprint(root: Path) -> str:
    h = hashlib.sha256()
    spawn_root = root / "data" / "spawnables"
    for path in sorted(p for p in spawn_root.rglob("*") if p.is_file() and p.suffix.lower() in {".txt", ".json"}):
        stat = path.stat()
        h.update(str(path.relative_to(root)).encode())
        h.update(str(stat.st_size).encode())
        h.update(str(stat.st_mtime_ns).encode())
    return h.hexdigest()


def _connect(path: str | Path, *, readonly: bool = False) -> sqlite3.Connection:
    p = Path(path).expanduser().resolve()
    if readonly:
        if not p.exists():
            raise AssetCatalogError(f"Asset catalog does not exist: {p}")
        con = sqlite3.connect(f"file:{p}?mode=ro", uri=True)
    else:
        p.parent.mkdir(parents=True, exist_ok=True)
        con = sqlite3.connect(p)
    con.row_factory = sqlite3.Row
    return con


def _create_schema(con: sqlite3.Connection) -> bool:
    con.executescript(
        """
        PRAGMA journal_mode=WAL;
        PRAGMA synchronous=NORMAL;
        CREATE TABLE IF NOT EXISTS meta (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        DROP TABLE IF EXISTS assets;
        CREATE TABLE assets (
            id INTEGER PRIMARY KEY,
            category TEXT NOT NULL,
            variant TEXT NOT NULL,
            module_path TEXT NOT NULL,
            data_type TEXT NOT NULL,
            name TEXT NOT NULL,
            file_name TEXT NOT NULL,
            spawn_data TEXT NOT NULL,
            extension TEXT NOT NULL,
            source_file TEXT NOT NULL,
            source_kind TEXT NOT NULL,
            template_json TEXT,
            search_text TEXT NOT NULL,
            UNIQUE(module_path, variant, spawn_data, name, source_file)
        );
        CREATE INDEX idx_assets_category ON assets(category);
        CREATE INDEX idx_assets_variant ON assets(variant);
        CREATE INDEX idx_assets_module ON assets(module_path);
        CREATE INDEX idx_assets_ext ON assets(extension);
        CREATE INDEX idx_assets_spawn_data ON assets(spawn_data);
        """
    )
    fts = True
    try:
        con.execute("DROP TABLE IF EXISTS asset_fts")
        con.execute(
            "CREATE VIRTUAL TABLE asset_fts USING fts5(name, file_name, spawn_data, category, variant, module_path, data_type, search_text, content='assets', content_rowid='id', tokenize='unicode61')"
        )
    except sqlite3.OperationalError:
        fts = False
    return fts


def build_catalog(world_builder_root: str | Path, db_path: str | Path | None = None) -> dict[str, Any]:
    root = find_worldbuilder_root(world_builder_root)
    db = Path(db_path).expanduser().resolve() if db_path else default_catalog_path(root)
    start = time.monotonic()
    con = _connect(db)
    try:
        fts = _create_schema(con)
        rows = []
        counts: dict[str, int] = {}
        total = 0
        for record in iter_asset_records(root):
            search_text = " ".join(
                part for part in (
                    record.name,
                    record.file_name,
                    record.spawn_data,
                    record.category,
                    record.variant,
                    record.module_path,
                    record.data_type,
                ) if part
            ).replace("\\", " ").replace("/", " ").replace("_", " ")
            rows.append((
                record.category,
                record.variant,
                record.module_path,
                record.data_type,
                record.name,
                record.file_name,
                record.spawn_data,
                record.extension,
                record.source_file,
                record.source_kind,
                record.template_json,
                search_text,
            ))
            if len(rows) >= 5000:
                before = con.total_changes
                con.executemany(
                    "INSERT OR IGNORE INTO assets(category,variant,module_path,data_type,name,file_name,spawn_data,extension,source_file,source_kind,template_json,search_text) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)",
                    rows,
                )
                total += con.total_changes - before
                rows.clear()
            key = f"{record.category}/{record.variant}"
            counts[key] = counts.get(key, 0) + 1
        if rows:
            before = con.total_changes
            con.executemany(
                "INSERT OR IGNORE INTO assets(category,variant,module_path,data_type,name,file_name,spawn_data,extension,source_file,source_kind,template_json,search_text) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)",
                rows,
            )
            total += con.total_changes - before
        if fts:
            con.execute("INSERT INTO asset_fts(asset_fts) VALUES('rebuild')")
        meta = {
            "schema": "1",
            "world_builder_root": str(root),
            "source_fingerprint": _source_fingerprint(root),
            "fts5": "1" if fts else "0",
            "built_at_unix": str(int(time.time())),
        }
        con.executemany("INSERT OR REPLACE INTO meta(key,value) VALUES(?,?)", meta.items())
        con.commit()
        actual = con.execute("SELECT COUNT(*) FROM assets").fetchone()[0]
        return {
            "database": str(db),
            "worldBuilderRoot": str(root),
            "assets": int(actual),
            "sourceRecords": int(sum(counts.values())),
            "fts5": fts,
            "seconds": round(time.monotonic() - start, 3),
            "counts": dict(sorted(counts.items())),
        }
    finally:
        con.close()


def catalog_info(db_path: str | Path) -> dict[str, Any]:
    con = _connect(db_path, readonly=True)
    try:
        meta = {row["key"]: row["value"] for row in con.execute("SELECT key,value FROM meta")}
        count = int(con.execute("SELECT COUNT(*) FROM assets").fetchone()[0])
        categories = [dict(row) for row in con.execute("SELECT category,variant,COUNT(*) AS count FROM assets GROUP BY category,variant ORDER BY category,variant")]
        return {"database": str(Path(db_path).resolve()), "assets": count, "meta": meta, "categories": categories}
    finally:
        con.close()


def _fts_query(query: str) -> str:
    # Keep Unicode letters/numbers and path-ish words, but never pass caller FTS
    # operators through to SQLite. Prefix search makes abbreviated resource names
    # practical while AND semantics keeps results useful for natural-language
    # terms such as "arasaka industrial wall".
    tokens = re.findall(r"[\w]+", query, flags=re.UNICODE)
    return " AND ".join(f'"{token}"*' for token in tokens if token)


def _row_to_result(row: sqlite3.Row) -> AssetSearchResult:
    template = None
    raw_template = row["template_json"]
    if raw_template:
        try:
            parsed = json.loads(raw_template)
            template = parsed if isinstance(parsed, dict) else None
        except json.JSONDecodeError:
            template = None
    rank = row["rank"] if "rank" in row.keys() else None
    return AssetSearchResult(
        id=int(row["id"]),
        category=str(row["category"]),
        variant=str(row["variant"]),
        module_path=str(row["module_path"]),
        data_type=str(row["data_type"]),
        name=str(row["name"]),
        file_name=str(row["file_name"]),
        spawn_data=str(row["spawn_data"]),
        extension=str(row["extension"]),
        source_file=str(row["source_file"]),
        source_kind=str(row["source_kind"]),
        template=template,
        rank=float(rank) if rank is not None else None,
    )


def search_catalog(
    db_path: str | Path,
    query: str,
    *,
    category: str | None = None,
    variant: str | None = None,
    module_path: str | None = None,
    extension: str | None = None,
    limit: int = 25,
) -> list[AssetSearchResult]:
    if limit < 1 or limit > 500:
        raise ValueError("limit must be between 1 and 500")
    con = _connect(db_path, readonly=True)
    try:
        meta = {row["key"]: row["value"] for row in con.execute("SELECT key,value FROM meta")}
        filters = []
        params: list[Any] = []
        if category:
            filters.append("a.category = ? COLLATE NOCASE")
            params.append(category)
        if variant:
            filters.append("a.variant = ? COLLATE NOCASE")
            params.append(variant)
        if module_path:
            filters.append("a.module_path = ? COLLATE NOCASE")
            params.append(module_path)
        if extension:
            ext = extension.lower()
            if ext and not ext.startswith("."):
                ext = "." + ext
            filters.append("a.extension = ?")
            params.append(ext)
        where = (" AND " + " AND ".join(filters)) if filters else ""
        fts_query = _fts_query(query)
        if meta.get("fts5") == "1" and fts_query:
            sql = (
                "SELECT a.*, bm25(asset_fts, 2.0, 3.0, 1.0, 0.4, 0.8, 0.5, 0.5, 0.25) AS rank "
                "FROM asset_fts JOIN assets a ON a.id=asset_fts.rowid WHERE asset_fts MATCH ?" + where + " ORDER BY rank, length(a.spawn_data), a.name LIMIT ?"
            )
            rows = con.execute(sql, [fts_query, *params, limit]).fetchall()
            # Natural language often contains one adjective that is absent from a
            # depot path. If strict AND has no hits, fall back to OR while keeping
            # the same ranking/filtering.
            if not rows and " AND " in fts_query:
                loose = fts_query.replace(" AND ", " OR ")
                rows = con.execute(sql, [loose, *params, limit]).fetchall()
        else:
            terms = re.findall(r"[\w]+", query, flags=re.UNICODE)
            like_filters = []
            like_params: list[str] = []
            for term in terms:
                like_filters.append("lower(a.search_text) LIKE ?")
                like_params.append(f"%{term.lower()}%")
            clause = " AND ".join(like_filters) if like_filters else "1=1"
            sql = "SELECT a.*, NULL AS rank FROM assets a WHERE " + clause + where + " ORDER BY length(a.spawn_data), a.name LIMIT ?"
            rows = con.execute(sql, [*like_params, *params, limit]).fetchall()
        return [_row_to_result(row) for row in rows]
    finally:
        con.close()


def get_asset(db_path: str | Path, asset_id: int) -> AssetSearchResult:
    con = _connect(db_path, readonly=True)
    try:
        row = con.execute("SELECT a.*, NULL AS rank FROM assets a WHERE id=?", (int(asset_id),)).fetchone()
        if row is None:
            raise AssetCatalogError(f"No asset with id {asset_id}")
        return _row_to_result(row)
    finally:
        con.close()


def resolve_asset(
    db_path: str | Path,
    query_or_id: str,
    *,
    module_path: str | None = None,
    variant: str | None = None,
) -> AssetSearchResult:
    if query_or_id.startswith("#") and query_or_id[1:].isdigit():
        result = get_asset(db_path, int(query_or_id[1:]))
        if module_path and result.module_path.lower() != module_path.lower():
            raise AssetCatalogError(f"Asset #{result.id} module is {result.module_path}, not {module_path}")
        if variant and result.variant.lower() != variant.lower():
            raise AssetCatalogError(f"Asset #{result.id} variant is {result.variant}, not {variant}")
        return result
    results = search_catalog(db_path, query_or_id, module_path=module_path, variant=variant, limit=2)
    if not results:
        raise AssetCatalogError(f"No asset matched {query_or_id!r}")
    if len(results) > 1:
        first, second = results[0], results[1]
        # Exact depot path or exact filename/name is deterministic; otherwise
        # force the caller/agent to choose an ID rather than silently guessing.
        q = query_or_id.lower()
        exact = [r for r in results if q in {r.spawn_data.lower(), r.file_name.lower(), r.name.lower()}]
        if len(exact) == 1:
            return exact[0]
        raise AssetCatalogError(
            f"Asset query is ambiguous; choose an ID (for example #{first.id} or #{second.id}) after running assets search"
        )
    return results[0]
