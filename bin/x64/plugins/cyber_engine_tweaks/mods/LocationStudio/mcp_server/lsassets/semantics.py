from __future__ import annotations

import json
import re
import sqlite3
import time
from pathlib import Path
from typing import Any

from .assets import AssetSearchResult, _connect
from .errors import Cp77wbError


class SemanticIndexError(Cp77wbError):
    pass


TAXONOMY: dict[str, dict[str, tuple[str, ...]]] = {
    "roles": {
        "wall": ("wall", "facade", "partition"),
        "floor": ("floor", "ground", "pavement", "sidewalk"),
        "ceiling": ("ceiling",),
        "door": ("door", "gate", "shutter"),
        "window": ("window", "glass_panel"),
        "light": ("light", "lamp", "neon", "emissive"),
        "sign": ("sign", "billboard", "advert", "poster", "graffiti"),
        "pipe": ("pipe", "duct", "vent", "hose"),
        "cable": ("cable", "wire", "conduit"),
        "column": ("column", "pillar", "support", "beam"),
        "stairs": ("stair", "stairs", "ladder", "ramp"),
        "fence": ("fence", "railing", "barrier", "guardrail"),
        "furniture": ("chair", "table", "desk", "sofa", "bed", "shelf", "cabinet", "bench"),
        "container": ("crate", "box", "container", "dumpster", "bin"),
        "vehicle": ("vehicle", "car", "truck", "bike", "motorcycle", "av_"),
        "plant": ("plant", "tree", "bush", "grass", "flower"),
        "stall": ("stall", "kiosk", "vendor", "booth", "stand"),
        "clutter": ("clutter", "trash", "debris", "garbage", "junk"),
        "device": ("device", "terminal", "elevator", "switch", "screen", "camera"),
    },
    "styles": {
        "arasaka": ("arasaka",),
        "militech": ("militech",),
        "kang_tao": ("kang_tao", "kangtao"),
        "trauma_team": ("trauma",),
        "nomad": ("nomad", "badlands"),
        "corpo": ("corpo", "corporate", "executive"),
        "industrial": ("industrial", "factory", "warehouse", "utility", "construction"),
        "japanese": ("japan", "japanese", "kabuki", "japantown"),
        "neon": ("neon",),
        "luxury": ("luxury", "lux", "premium", "penthouse"),
        "street": ("street", "urban", "city"),
    },
    "materials": {
        "concrete": ("concrete", "cement"),
        "metal": ("metal", "steel", "iron", "aluminium", "aluminum"),
        "glass": ("glass",),
        "wood": ("wood", "wooden"),
        "plastic": ("plastic",),
        "fabric": ("fabric", "cloth", "textile"),
        "stone": ("stone", "brick", "marble", "granite"),
    },
    "conditions": {
        "clean": ("clean", "new", "pristine"),
        "dirty": ("dirty", "grime", "grimy"),
        "damaged": ("damaged", "damage", "broken", "destroyed", "cracked", "ruined"),
        "rusty": ("rust", "rusty", "corroded"),
        "abandoned": ("abandoned", "derelict"),
        "burned": ("burned", "burnt", "charred"),
    },
}


def _normalize(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", value.lower().replace("\\", "/")).strip("_")


# Normalizing taxonomy needles for every one of ~359k assets was needlessly
# expensive. Build this once at import time.
_NORMALIZED_TAXONOMY: dict[str, dict[str, tuple[str, ...]]] = {
    facet: {canonical: tuple(_normalize(n) for n in needles) for canonical, needles in values.items()}
    for facet, values in TAXONOMY.items()
}


def _tokens(value: str) -> set[str]:
    norm = _normalize(value)
    return {t for t in norm.split("_") if t and len(t) > 1}


def infer_semantics(asset: AssetSearchResult | dict[str, Any]) -> dict[str, list[str]]:
    def get(key: str, default: str = "") -> str:
        if isinstance(asset, dict):
            return str(asset.get(key, default) or default)
        return str(getattr(asset, key, default) or default)

    corpus = " ".join(
        get(k) for k in ("name", "file_name", "spawn_data", "category", "variant", "module_path", "data_type")
    )
    norm = _normalize(corpus)
    padded = f"_{norm}_"
    token_set = _tokens(corpus)
    result: dict[str, list[str]] = {}
    tags: set[str] = set()
    for facet, values in _NORMALIZED_TAXONOMY.items():
        hits: list[str] = []
        for canonical, needles in values.items():
            if any(f"_{n}_" in padded for n in needles):
                hits.append(canonical)
                tags.add(canonical)
        result[facet] = sorted(set(hits))
    # Preserve useful path vocabulary without turning every directory component
    # into a semantic assertion. These are searchable tags, not ontology facets.
    stop = {"base", "environment", "architecture", "decoration", "common", "gameplay", "mesh", "entity", "template", "static"}
    lexical = sorted(t for t in token_set if t not in stop and (len(t) >= 4 or t.isdigit()))
    tags.update(lexical[:24])
    result["tags"] = sorted(tags)
    return result


def _load_overrides(value: str | Path | None) -> list[dict[str, Any]]:
    if value is None:
        return []
    p = Path(value)
    raw = p.read_text(encoding="utf-8-sig") if p.is_file() else str(value)
    data = json.loads(raw)
    if isinstance(data, dict):
        data = data.get("overrides", [])
    if not isinstance(data, list):
        raise SemanticIndexError("Semantic overrides must be an array or {overrides:[...]}")
    return [x for x in data if isinstance(x, dict)]


def _override_for(asset_id: int, spawn_data: str, overrides: list[dict[str, Any]]) -> list[dict[str, Any]]:
    out = []
    low = spawn_data.lower()
    for entry in overrides:
        selector = str(entry.get("asset", ""))
        contains = str(entry.get("contains", ""))
        if selector == f"#{asset_id}" or (contains and contains.lower() in low):
            out.append(entry)
    return out


def build_semantic_index(db_path: str | Path, overrides: str | Path | None = None) -> dict[str, Any]:
    override_entries = _load_overrides(overrides)
    con = _connect(db_path)
    start = time.monotonic()
    try:
        con.executescript(
            """
            DROP TABLE IF EXISTS asset_semantics;
            CREATE TABLE asset_semantics (
                asset_id INTEGER PRIMARY KEY,
                roles TEXT NOT NULL,
                styles TEXT NOT NULL,
                materials TEXT NOT NULL,
                conditions TEXT NOT NULL,
                tags TEXT NOT NULL,
                search_text TEXT NOT NULL,
                source TEXT NOT NULL DEFAULT 'derived',
                FOREIGN KEY(asset_id) REFERENCES assets(id)
            );
            """
        )
        fts = True
        try:
            con.execute("DROP TABLE IF EXISTS semantic_fts")
            con.execute(
                "CREATE VIRTUAL TABLE semantic_fts USING fts5(search_text, roles, styles, materials, conditions, tags, content='asset_semantics', content_rowid='asset_id', tokenize='unicode61')"
            )
        except sqlite3.OperationalError:
            fts = False
        rows: list[tuple[Any, ...]] = []
        facets_count: dict[str, int] = {}
        for row in con.execute("SELECT * FROM assets ORDER BY id"):
            asset = dict(row)
            inferred = infer_semantics(asset)
            source = "derived"
            for override in _override_for(int(row["id"]), str(row["spawn_data"]), override_entries):
                source = "derived+override"
                for key in ("roles", "styles", "materials", "conditions", "tags"):
                    vals = override.get(key)
                    if isinstance(vals, list):
                        inferred[key] = sorted(set(inferred.get(key, []) + [str(v).strip().lower() for v in vals if str(v).strip()]))
            for key in ("roles", "styles", "materials", "conditions"):
                for item in inferred[key]:
                    facets_count[f"{key}:{item}"] = facets_count.get(f"{key}:{item}", 0) + 1
            # Keep the semantic index compact. The base asset_fts already indexes
            # full depot paths/names; this FTS layer only needs derived facets/tags.
            search_text = " ".join([
                *inferred["roles"], *inferred["styles"], *inferred["materials"], *inferred["conditions"], *inferred["tags"],
            ]).replace("_", " ")
            rows.append((
                int(row["id"]), json.dumps(inferred["roles"]), json.dumps(inferred["styles"]),
                json.dumps(inferred["materials"]), json.dumps(inferred["conditions"]), json.dumps(inferred["tags"]),
                search_text, source,
            ))
            if len(rows) >= 5000:
                con.executemany("INSERT INTO asset_semantics(asset_id,roles,styles,materials,conditions,tags,search_text,source) VALUES(?,?,?,?,?,?,?,?)", rows)
                rows.clear()
        if rows:
            con.executemany("INSERT INTO asset_semantics(asset_id,roles,styles,materials,conditions,tags,search_text,source) VALUES(?,?,?,?,?,?,?,?)", rows)
        if fts:
            con.execute("INSERT INTO semantic_fts(semantic_fts) VALUES('rebuild')")
        con.execute("INSERT OR REPLACE INTO meta(key,value) VALUES('semantic_schema','1')")
        con.execute("INSERT OR REPLACE INTO meta(key,value) VALUES('semantic_fts5',?)", ("1" if fts else "0",))
        con.commit()
        count = int(con.execute("SELECT COUNT(*) FROM asset_semantics").fetchone()[0])
        return {
            "database": str(Path(db_path).resolve()), "assets": count, "fts5": fts,
            "overrides": len(override_entries), "seconds": round(time.monotonic() - start, 3),
            "facets": dict(sorted(facets_count.items())),
        }
    finally:
        con.close()


def _decode_list(raw: str) -> list[str]:
    try:
        value = json.loads(raw)
        return [str(x) for x in value] if isinstance(value, list) else []
    except json.JSONDecodeError:
        return []


def semantic_search(
    db_path: str | Path,
    query: str,
    *, role: str | None = None, style: str | None = None, material: str | None = None,
    condition: str | None = None, category: str | None = None, variant: str | None = None,
    limit: int = 25,
) -> list[dict[str, Any]]:
    if not (1 <= limit <= 500):
        raise ValueError("limit must be between 1 and 500")
    con = _connect(db_path, readonly=True)
    try:
        try:
            count = con.execute("SELECT COUNT(*) FROM asset_semantics").fetchone()[0]
        except sqlite3.OperationalError as exc:
            raise SemanticIndexError("Semantic index is missing; run semantic-build first") from exc
        if not count:
            return []
        meta = {r["key"]: r["value"] for r in con.execute("SELECT key,value FROM meta")}
        filters: list[str] = []
        params: list[Any] = []
        for column, value in (("roles", role), ("styles", style), ("materials", material), ("conditions", condition)):
            if value:
                filters.append(f"lower(s.{column}) LIKE ?")
                params.append(f'%"{value.lower()}"%')
        if category:
            filters.append("a.category = ? COLLATE NOCASE")
            params.append(category)
        if variant:
            filters.append("a.variant = ? COLLATE NOCASE")
            params.append(variant)
        where = (" AND " + " AND ".join(filters)) if filters else ""
        tokens = re.findall(r"[\w]+", query, flags=re.UNICODE)
        if meta.get("semantic_fts5") == "1" and tokens:
            ftsq = " AND ".join(f'"{t}"*' for t in tokens)
            sql = (
                "SELECT a.*,s.roles,s.styles,s.materials,s.conditions,s.tags,s.source,bm25(semantic_fts,1.0,2.0,1.4,1.2,1.0,0.8) AS semantic_rank "
                "FROM semantic_fts JOIN asset_semantics s ON s.asset_id=semantic_fts.rowid JOIN assets a ON a.id=s.asset_id "
                "WHERE semantic_fts MATCH ?" + where + " ORDER BY semantic_rank,length(a.spawn_data),a.id LIMIT ?"
            )
            rows = con.execute(sql, [ftsq, *params, limit]).fetchall()
            if not rows and len(tokens) > 1:
                rows = con.execute(sql, [" OR ".join(f'"{t}"*' for t in tokens), *params, limit]).fetchall()
        else:
            clauses = ["lower(s.search_text) LIKE ?" for _ in tokens] or ["1=1"]
            like_params = [f"%{t.lower()}%" for t in tokens]
            sql = (
                "SELECT a.*,s.roles,s.styles,s.materials,s.conditions,s.tags,s.source,NULL AS semantic_rank "
                "FROM asset_semantics s JOIN assets a ON a.id=s.asset_id WHERE " + " AND ".join(clauses) + where +
                " ORDER BY length(a.spawn_data),a.id LIMIT ?"
            )
            rows = con.execute(sql, [*like_params, *params, limit]).fetchall()
        out: list[dict[str, Any]] = []
        for row in rows:
            out.append({
                "id": int(row["id"]), "category": row["category"], "variant": row["variant"], "module_path": row["module_path"],
                "data_type": row["data_type"], "name": row["name"], "file_name": row["file_name"], "spawn_data": row["spawn_data"],
                "roles": _decode_list(row["roles"]), "styles": _decode_list(row["styles"]), "materials": _decode_list(row["materials"]),
                "conditions": _decode_list(row["conditions"]), "tags": _decode_list(row["tags"]), "semantic_source": row["source"],
                "rank": float(row["semantic_rank"]) if row["semantic_rank"] is not None else None,
            })
        return out
    finally:
        con.close()
