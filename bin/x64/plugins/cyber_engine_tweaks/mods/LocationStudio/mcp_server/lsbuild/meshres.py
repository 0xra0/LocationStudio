"""Native Cyberpunk mesh resources from generated geometry.

Turns a triangle mesh (``procedural.Mesh``) into a complete WolvenKit CR2W-JSON
``CMesh`` document, which the WolvenKit worker (``deserialize``) writes as a
binary ``.mesh``:

* one render chunk (submesh) per material slot, split at 65 535 vertices;
* a vertex buffer laid out stream by stream in the chunk's vertex layout, with
  quantized positions (``quantizationScale`` / ``quantizationOffset``),
  packed normals and tangents, UVs and vertex colour;
* a 16-bit index buffer after the vertex data (``indexBufferOffset``);
* bounds, per-axis surface area, LOD metadata (``lodLevelInfo`` and chunk LOD
  masks), material entries, external material references and one appearance
  per material set.

The vertex layout, the chunk's vertex factory/render masks and the blob header
constants are taken from a **reference static mesh** exported to JSON with
WolvenKit when one is given (``layout_source: reference``). Otherwise a built-in
static-mesh layout is used and reported as ``builtin-unverified``: verify such
meshes in game before shipping them.

``decode`` reads a CMesh JSON document (ours or one exported by WolvenKit)
back into chunks, layouts, materials and decoded vertex data.
"""
from __future__ import annotations

import base64
import copy
import json
import math
import struct
from pathlib import Path
from typing import Any

WKIT_VERSION = "8.16.0"
WKIT_JSON_VERSION = "0.0.8"
MAX_CHUNK_VERTICES = 65535

# Size in bytes and component count of each packing type.
PACKING = {
    "PT_Float1": (4, 1), "PT_Float2": (8, 2), "PT_Float3": (12, 3), "PT_Float4": (16, 4),
    "PT_Float16_2": (4, 2), "PT_Float16_4": (8, 4),
    "PT_Short2N": (4, 2), "PT_Short4N": (8, 4), "PT_Short4": (8, 4),
    "PT_UShort2N": (4, 2), "PT_UShort4N": (8, 4),
    "PT_Dec4": (4, 4), "PT_Color": (4, 4), "PT_UByte4": (4, 4), "PT_UByte4N": (4, 4), "PT_Byte4N": (4, 4),
    "PT_UInt1": (4, 1),
}
SKINNING = {"PS_SkinIndices", "PS_SkinWeights", "PS_ExtraData"}

# Best-known layout of static meshes. Used only without a reference mesh.
BUILTIN_LAYOUT = [
    {"usage": "PS_Position", "type": "PT_Short4N", "usageIndex": 0, "streamIndex": 0},
    {"usage": "PS_TexCoord", "type": "PT_Float16_2", "usageIndex": 0, "streamIndex": 1},
    {"usage": "PS_Normal", "type": "PT_Dec4", "usageIndex": 0, "streamIndex": 2},
    {"usage": "PS_Tangent", "type": "PT_Dec4", "usageIndex": 0, "streamIndex": 2},
    {"usage": "PS_Color", "type": "PT_Color", "usageIndex": 0, "streamIndex": 3},
    {"usage": "PS_TexCoord", "type": "PT_Float16_2", "usageIndex": 1, "streamIndex": 3},
]
BUILTIN_VERTEX_FACTORY = 2


def _enum(v: Any) -> str:
    if isinstance(v, dict):
        v = v.get("$value", v.get("value"))
    return str(v)


def _int(v: Any, default: int = 0) -> int:
    if isinstance(v, dict):
        v = v.get("$value", v.get("value"))
    try:
        return int(v)
    except (TypeError, ValueError):
        return default


def cname(value: str) -> dict[str, Any]:
    return {"$type": "CName", "$storage": "string", "$value": value}


def vec4(x: float, y: float, z: float, w: float) -> dict[str, Any]:
    return {"$type": "Vector4", "W": w, "X": x, "Y": y, "Z": z}


def depot(path: str, flags: str = "Default") -> dict[str, Any]:
    return {"DepotPath": {"$type": "ResourcePath", "$storage": "string", "$value": path}, "Flags": flags}


# --------------------------------------------------------------------------- layout

class Layout:
    def __init__(self, elements: list[dict[str, Any]], strides: list[int] | None = None, source: str = "builtin-unverified"):
        self.elements = []
        for e in elements:
            etype, usage = _enum(e.get("type")), _enum(e.get("usage"))
            if etype not in PACKING:
                raise ValueError(f"unsupported vertex packing type {etype}")
            if usage in SKINNING:
                raise ValueError(f"the layout has {usage}: use a static (unskinned) reference mesh")
            if _enum(e.get("streamType", "ST_PerVertex")) not in ("ST_PerVertex", "None"):
                continue
            self.elements.append({"type": etype, "usage": usage, "usageIndex": _int(e.get("usageIndex")), "streamIndex": _int(e.get("streamIndex"))})
        self.source = source
        self.streams = sorted({e["streamIndex"] for e in self.elements})
        self.offsets: dict[int, int] = {}
        computed: dict[int, int] = {}
        for i, e in enumerate(self.elements):
            s = e["streamIndex"]
            self.offsets[i] = computed.get(s, 0)
            computed[s] = computed.get(s, 0) + PACKING[e["type"]][0]
        self.strides = dict(computed)
        for s, stride in enumerate(strides or []):
            if s in self.strides and int(stride) >= self.strides[s]:
                self.strides[s] = int(stride)
        if not any(e["usage"] == "PS_Position" for e in self.elements):
            raise ValueError("the vertex layout has no PS_Position element")

    def json(self) -> dict[str, Any]:
        slot_strides = [self.strides.get(s, 0) for s in range(8)]
        mask = sum(1 << s for s in self.streams)
        return {"$type": "GpuWrapApiVertexLayoutDesc",
                "elements": [{"$type": "GpuWrapApiVertexPackingPackingElement", "type": e["type"], "usage": e["usage"],
                              "usageIndex": e["usageIndex"], "streamIndex": e["streamIndex"], "streamType": "ST_PerVertex"}
                             for e in self.elements],
                "hash": 0, "slotMask": mask, "slotStrides": slot_strides}

    @classmethod
    def from_json(cls, layout: dict[str, Any], source: str) -> "Layout":
        return cls(layout.get("elements") or [], [int(s) for s in (layout.get("slotStrides") or [])], source)


def _unorm(v: float, bits: int) -> int:
    return max(0, min((1 << bits) - 1, int(round((max(-1.0, min(1.0, v)) * 0.5 + 0.5) * ((1 << bits) - 1)))))


def encode(etype: str, values: tuple[float, ...]) -> bytes:
    size, count = PACKING[etype]
    v = list(values) + [0.0] * (count - len(values))
    v = v[:count]
    if etype.startswith("PT_Float16"):
        return struct.pack(f"<{count}e", *v)
    if etype.startswith("PT_Float"):
        return struct.pack(f"<{count}f", *v)
    if etype in ("PT_Short2N", "PT_Short4N"):
        return struct.pack(f"<{count}h", *(int(round(max(-1.0, min(1.0, x)) * 32767)) for x in v))
    if etype == "PT_Short4":
        return struct.pack("<4h", *(int(round(x)) for x in v))
    if etype in ("PT_UShort2N", "PT_UShort4N"):
        return struct.pack(f"<{count}H", *(int(round(max(0.0, min(1.0, x)) * 65535)) for x in v))
    if etype == "PT_Dec4":
        x, y, z = (_unorm(c, 10) for c in v[:3])
        w = 3 if v[3] >= 0 else 0
        return struct.pack("<I", x | (y << 10) | (z << 20) | (w << 30))
    if etype in ("PT_Color", "PT_UByte4N"):
        return struct.pack("<4B", *(int(round(max(0.0, min(1.0, x)) * 255)) for x in v))
    if etype == "PT_Byte4N":
        return struct.pack("<4b", *(int(round(max(-1.0, min(1.0, x)) * 127)) for x in v))
    if etype == "PT_UByte4":
        return struct.pack("<4B", *(int(max(0, min(255, round(x)))) for x in v))
    if etype == "PT_UInt1":
        return struct.pack("<I", int(v[0]))
    raise ValueError(etype)


def decode_value(etype: str, raw: bytes) -> tuple[float, ...]:
    size, count = PACKING[etype]
    if etype.startswith("PT_Float16"):
        return struct.unpack(f"<{count}e", raw)
    if etype.startswith("PT_Float"):
        return struct.unpack(f"<{count}f", raw)
    if etype in ("PT_Short2N", "PT_Short4N"):
        return tuple(x / 32767 for x in struct.unpack(f"<{count}h", raw))
    if etype == "PT_Short4":
        return tuple(float(x) for x in struct.unpack("<4h", raw))
    if etype in ("PT_UShort2N", "PT_UShort4N"):
        return tuple(x / 65535 for x in struct.unpack(f"<{count}H", raw))
    if etype == "PT_Dec4":
        (p,) = struct.unpack("<I", raw)
        return tuple(((p >> (10 * i)) & 1023) / 1023 * 2 - 1 for i in range(3)) + ((1.0 if (p >> 30) else -1.0),)
    if etype in ("PT_Color", "PT_UByte4N"):
        return tuple(x / 255 for x in struct.unpack("<4B", raw))
    if etype == "PT_Byte4N":
        return tuple(x / 127 for x in struct.unpack("<4b", raw))
    if etype == "PT_UByte4":
        return tuple(float(x) for x in struct.unpack("<4B", raw))
    return tuple(float(x) for x in struct.unpack("<I", raw))


# --------------------------------------------------------------------------- geometry helpers

def _tangents(pos, nrm, uv, idx) -> list[tuple[float, float, float, float]]:
    acc = [[0.0, 0.0, 0.0] for _ in pos]
    bit = [[0.0, 0.0, 0.0] for _ in pos]
    for t in range(0, len(idx), 3):
        a, b, c = idx[t], idx[t + 1], idx[t + 2]
        e1 = [pos[b][k] - pos[a][k] for k in range(3)]
        e2 = [pos[c][k] - pos[a][k] for k in range(3)]
        du1, dv1 = uv[b][0] - uv[a][0], uv[b][1] - uv[a][1]
        du2, dv2 = uv[c][0] - uv[a][0], uv[c][1] - uv[a][1]
        det = du1 * dv2 - du2 * dv1
        if abs(det) < 1e-12:
            continue
        r = 1.0 / det
        tan = [(e1[k] * dv2 - e2[k] * dv1) * r for k in range(3)]
        bi = [(e2[k] * du1 - e1[k] * du2) * r for k in range(3)]
        for v in (a, b, c):
            for k in range(3):
                acc[v][k] += tan[k]
                bit[v][k] += bi[k]
    out = []
    for i, n in enumerate(nrm):
        t = acc[i]
        d = sum(t[k] * n[k] for k in range(3))
        t = [t[k] - n[k] * d for k in range(3)]
        length = math.sqrt(sum(x * x for x in t))
        if length < 1e-9:
            # Any unit vector perpendicular to the normal.
            base = (1.0, 0.0, 0.0) if abs(n[0]) < 0.9 else (0.0, 1.0, 0.0)
            t = [base[1] * n[2] - base[2] * n[1], base[2] * n[0] - base[0] * n[2], base[0] * n[1] - base[1] * n[0]]
            length = math.sqrt(sum(x * x for x in t)) or 1.0
        t = [x / length for x in t]
        cross = (n[1] * t[2] - n[2] * t[1], n[2] * t[0] - n[0] * t[2], n[0] * t[1] - n[1] * t[0])
        w = 1.0 if sum(cross[k] * bit[i][k] for k in range(3)) >= 0 else -1.0
        out.append((t[0], t[1], t[2], w))
    return out


def _split(prim: dict[str, list]) -> list[dict[str, list]]:
    """Split one material primitive into chunks of at most 65 535 vertices."""
    if len(prim["pos"]) <= MAX_CHUNK_VERTICES:
        return [prim]
    chunks, cur, remap = [], None, {}
    for t in range(0, len(prim["idx"]), 3):
        tri = prim["idx"][t:t + 3]
        if cur is None or len(cur["pos"]) + 3 > MAX_CHUNK_VERTICES:
            cur = {"pos": [], "nrm": [], "uv": [], "idx": []}
            chunks.append(cur)
            remap = {}
        for v in tri:
            if v not in remap:
                remap[v] = len(cur["pos"])
                for key in ("pos", "nrm", "uv"):
                    cur[key].append(prim[key][v])
            cur["idx"].append(remap[v])
    return chunks


def _align(n: int, a: int) -> int:
    return (n + a - 1) // a * a


# --------------------------------------------------------------------------- building

def _reference(doc: dict[str, Any] | None) -> tuple[dict[str, Any] | None, dict[str, Any] | None, dict[str, Any] | None]:
    """(root CMesh, blob, first chunk) of a reference document, if any."""
    if not doc:
        return None, None, None
    root = ((doc.get("Data") or {}).get("RootChunk")) or doc
    if root.get("$type") != "CMesh":
        raise ValueError(f"reference is a {root.get('$type')}, not a CMesh")
    blob = ((root.get("renderResourceBlob") or {}).get("Data")) or {}
    chunks = ((blob.get("header") or {}).get("renderChunkInfos")) or []
    return root, blob, (chunks[0] if chunks else None)


def build_mesh_resource(mesh: Any, materials: dict[str, str], *, reference: dict[str, Any] | None = None,
                        appearance: str = "default", lod_distances: list[float] | None = None,
                        appearances: dict[str, dict[str, str]] | None = None) -> dict[str, Any]:
    """CMesh CR2W-JSON document plus statistics. `materials` maps each material slot to a .mi/.mt depot path.

    `appearances` adds named appearances (name -> slot -> path) next to the default one, e.g. material variants."""
    ref_root, ref_blob, ref_chunk = _reference(reference)
    if ref_chunk is not None:
        layout = Layout.from_json((ref_chunk.get("chunkVertices") or {}).get("vertexLayout") or {}, "reference")
    else:
        layout = Layout(BUILTIN_LAYOUT)
    slots = [name for name, prim in sorted(mesh.prims.items()) if prim["idx"]]
    if not slots:
        raise ValueError("the mesh has no triangles")
    missing = [s for s in slots if not materials.get(s)]
    if missing:
        raise ValueError(f"no material for slot(s) {', '.join(missing)}; map every slot to a .mi or .mt depot path")
    for s in slots:
        if not str(materials[s]).lower().endswith((".mi", ".mt", ".remt")):
            raise ValueError(f"material for slot {s} must be a .mi/.mt/.remt depot path, got {materials[s]!r}")

    looks: list[tuple[str, dict[str, str]]] = [(appearance, {s: materials[s] for s in slots})]
    for name, look in (appearances or {}).items():
        if name in (appearance, "default"):
            continue
        for s in slots:
            p = str(look.get(s) or materials[s])
            if not p.lower().endswith((".mi", ".mt", ".remt")):
                raise ValueError(f"appearance {name}: material for slot {s} must be a .mi/.mt/.remt depot path, got {p!r}")
        looks.append((str(name), {s: str(look.get(s) or materials[s]) for s in slots}))
    entries: list[tuple[str, str]] = []  # (entry name, path)
    look_entries: list[dict[str, str]] = []
    for li, (name, look) in enumerate(looks):
        names = {}
        for s in slots:
            hit = next((en for en, ep in entries if ep == look[s] and (en == s or en.startswith(s + "@"))), None)
            if hit is None:
                hit = s if li == 0 else f"{s}@{name}"
                entries.append((hit, look[s]))
            names[s] = hit
        look_entries.append(names)
    all_pos = [p for s in slots for p in mesh.prims[s]["pos"]]
    lo = [min(p[k] for p in all_pos) for k in range(3)]
    hi = [max(p[k] for p in all_pos) for k in range(3)]
    q_off = [(lo[k] + hi[k]) / 2 for k in range(3)]
    q_scale = [max((hi[k] - lo[k]) / 2, 1e-4) for k in range(3)]

    chunk_data = []
    for slot_index, slot in enumerate(slots):
        for part in _split(mesh.prims[slot]):
            chunk_data.append((slot_index, slot, part))

    vertex = bytearray()
    chunk_offsets = []
    for _slot_index, _slot, part in chunk_data:
        tangents = _tangents(part["pos"], part["nrm"], part["uv"], part["idx"])
        offsets = {}
        for stream in layout.streams:
            while len(vertex) % 16:
                vertex.append(0)
            offsets[stream] = len(vertex)
            stride = layout.strides[stream]
            for v in range(len(part["pos"])):
                start = len(vertex)
                for i, e in enumerate(layout.elements):
                    if e["streamIndex"] != stream:
                        continue
                    usage, ui = e["usage"], e["usageIndex"]
                    if usage == "PS_Position":
                        p = part["pos"][v]
                        values = (tuple((p[k] - q_off[k]) / q_scale[k] for k in range(3)) + (1.0,)) if e["type"] in ("PT_Short4N", "PT_Short2N") else (p[0], p[1], p[2], 1.0)
                    elif usage == "PS_Normal":
                        n = part["nrm"][v]
                        values = (n[0], n[1], n[2], 1.0)
                    elif usage == "PS_Tangent":
                        values = tangents[v]
                    elif usage == "PS_TexCoord":
                        u, w = part["uv"][v]
                        values = (u, w)
                    elif usage == "PS_Color":
                        values = (1.0, 1.0, 1.0, 1.0)
                    else:
                        values = (0.0, 0.0, 0.0, 0.0)
                    vertex.extend(encode(e["type"], values))
                vertex.extend(b"\0" * (stride - (len(vertex) - start)))
        chunk_offsets.append(offsets)
    vertex_size = len(vertex)
    index_offset = _align(vertex_size, 16)
    index = bytearray()
    index_offsets = []
    for _slot_index, _slot, part in chunk_data:
        while len(index) % 4:
            index.append(0)
        index_offsets.append(len(index))
        index.extend(struct.pack(f"<{len(part['idx'])}H", *part["idx"]))
    buffer = bytes(vertex) + b"\0" * (index_offset - vertex_size) + bytes(index)

    lod_levels = [0.0] + [float(d) for d in (lod_distances or [])]
    chunks_json = []
    for (slot_index, slot, part), offsets, ioff in zip(chunk_data, chunk_offsets, index_offsets):
        chunk = copy.deepcopy(ref_chunk) if ref_chunk is not None else {"$type": "rendChunk", "vertexFactory": BUILTIN_VERTEX_FACTORY,
                                                                         "renderMask": 0, "mergedRenderMask": 0}
        chunk["$type"] = "rendChunk"
        chunk["numVertices"] = len(part["pos"])
        chunk["numIndices"] = len(part["idx"])
        chunk["materialId"] = slot_index
        chunk["lodMask"] = 1
        byte_offsets = [offsets.get(s, 0) for s in range(5)]
        chunk["chunkVertices"] = {"$type": "rendVertexBufferChunk", "byteOffsets": byte_offsets, "vertexLayout": layout.json()}
        chunk["chunkIndices"] = {"$type": "rendIndexBufferChunk", "pe": "IBCT_Uint16", "teOffset": ioff}
        chunks_json.append(chunk)

    header = copy.deepcopy((ref_blob or {}).get("header") or {}) if ref_blob else {"$type": "rendRenderMeshBlobHeader", "version": 21, "dataProcessing": 0}
    header["$type"] = "rendRenderMeshBlobHeader"
    header.update({"vertexBufferSize": vertex_size, "indexBufferSize": len(index), "indexBufferOffset": index_offset,
                   "renderChunkInfos": chunks_json, "quantizationScale": vec4(*q_scale, 0), "quantizationOffset": vec4(*q_off, 1),
                   "bonePositions": []})
    for key in ("opacityMicromaps", "speedTreeWind"):
        header.pop(key, None)
    blob = copy.deepcopy(ref_blob) if ref_blob else {}
    blob.update({"$type": "rendRenderMeshBlob", "header": header,
                 "renderBuffer": {"BufferId": "1", "Flags": 0, "Bytes": base64.b64encode(buffer).decode("ascii")}})

    area = [0.0, 0.0, 0.0]
    for s in slots:
        prim = mesh.prims[s]
        p, idx = prim["pos"], prim["idx"]
        for t in range(0, len(idx), 3):
            a, b, c = p[idx[t]], p[idx[t + 1]], p[idx[t + 2]]
            e1 = [b[k] - a[k] for k in range(3)]
            e2 = [c[k] - a[k] for k in range(3)]
            cr = (e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0])
            for k in range(3):
                area[k] += abs(cr[k]) / 2

    handle = [0]

    def h(data: dict[str, Any]) -> dict[str, Any]:
        handle[0] += 1
        return {"HandleId": str(handle[0] - 1), "Data": data}

    root = copy.deepcopy(ref_root) if ref_root else {}
    root.update({
        "$type": "CMesh", "cookingPlatform": root.get("cookingPlatform", "PLATFORM_PC"),
        "boundingBox": {"$type": "Box", "Max": vec4(*hi, 1), "Min": vec4(*lo, 1)},
        "surfaceAreaPerAxis": {"$type": "Vector3", "X": area[0], "Y": area[1], "Z": area[2]},
        "renderResourceBlob": h(blob),
        "appearances": [h({"$type": "meshMeshAppearance", "name": cname(name),
                           "chunkMaterials": [cname(look_entries[li][slot]) for _i, slot, _p in chunk_data], "tags": []})
                        for li, (name, _look) in enumerate(looks)],
        "materialEntries": [{"$type": "CMeshMaterialEntry", "name": cname(en), "index": i, "isLocalInstance": 0} for i, (en, _p) in enumerate(entries)],
        "externalMaterials": [depot(ep, "Soft") for _en, ep in entries],
        "localMaterialBuffer": {"$type": "meshMeshMaterialBuffer", "rawData": {"BufferId": "2", "Flags": 0, "Bytes": None}, "rawDataHeaders": []},
        "localMaterialInstances": [], "preloadLocalMaterialInstances": [], "preloadExternalMaterials": [],
        "lodLevelInfo": lod_levels, "boneNames": [], "boneRigMatrices": [], "boneVertexEpsilons": [], "lodBoneMask": [],
        "parameters": [], "objectType": root.get("objectType", "MeshType_Static") if ref_root else "MeshType_Static",
    })
    doc = {"Header": {"WolvenKitVersion": WKIT_VERSION, "WKitJsonVersion": WKIT_JSON_VERSION, "DataType": "CR2W",
                      "GeneratedBy": "LocationStudio procedural geometry"},
           "Data": {"Version": 195, "BuildVersion": 0, "RootChunk": root, "EmbeddedFiles": []}}
    stats = {"chunks": len(chunks_json), "slots": slots, "vertices": sum(c["numVertices"] for c in chunks_json),
             "indices": sum(c["numIndices"] for c in chunks_json), "vertex_buffer_bytes": vertex_size, "index_buffer_bytes": len(index),
             "bounds": {"min": lo, "max": hi}, "layout_source": layout.source, "lod_levels": lod_levels,
             "materials": [materials[s] for s in slots], "appearances": [name for name, _l in looks]}
    if layout.source != "reference":
        stats["warning"] = ("built-in static-mesh vertex layout; give a WolvenKit JSON export of a vanilla static mesh as the "
                            "reference so the layout, vertex factory and header constants match the game, and verify in game")
    return {"document": doc, "stats": stats}


# --------------------------------------------------------------------------- decoding

def decode(doc: dict[str, Any], *, vertices: bool = False) -> dict[str, Any]:
    """Summarize (and optionally decode) a CMesh CR2W-JSON document."""
    root = ((doc.get("Data") or {}).get("RootChunk")) or doc
    if root.get("$type") != "CMesh":
        raise ValueError(f"not a CMesh document ({root.get('$type')})")
    blob = (root.get("renderResourceBlob") or {}).get("Data") or {}
    header = blob.get("header") or {}
    raw = (blob.get("renderBuffer") or {}).get("Bytes")
    buffer = base64.b64decode(raw) if isinstance(raw, str) else b""
    qs, qo = header.get("quantizationScale") or {}, header.get("quantizationOffset") or {}
    scale = [float(qs.get(k, 1)) for k in ("X", "Y", "Z")]
    offset = [float(qo.get(k, 0)) for k in ("X", "Y", "Z")]
    index_base = _int(header.get("indexBufferOffset"))
    chunks = []
    for ci, ch in enumerate(header.get("renderChunkInfos") or []):
        cv = ch.get("chunkVertices") or {}
        layout = Layout.from_json(cv.get("vertexLayout") or {}, "document")
        byte_offsets = [_int(x) for x in (cv.get("byteOffsets") or [])]
        n, ni = _int(ch.get("numVertices")), _int(ch.get("numIndices"))
        info: dict[str, Any] = {"index": ci, "vertices": n, "indices": ni, "material_id": _int(ch.get("materialId")),
                                "lod_mask": _int(ch.get("lodMask")), "vertex_factory": _int(ch.get("vertexFactory")),
                                "layout": [f"{e['usage']}{e['usageIndex']}:{e['type']}@{e['streamIndex']}" for e in layout.elements],
                                "strides": layout.strides}
        if vertices and buffer:
            attrs: dict[str, list] = {}
            for i, e in enumerate(layout.elements):
                size = PACKING[e["type"]][0]
                base = byte_offsets[e["streamIndex"]] + layout.offsets[i]
                stride = layout.strides[e["streamIndex"]]
                vals = [decode_value(e["type"], buffer[base + v * stride: base + v * stride + size]) for v in range(n)]
                key = f"{e['usage']}{e['usageIndex']}"
                if e["usage"] == "PS_Position" and e["type"] in ("PT_Short4N", "PT_Short2N"):
                    vals = [tuple(val[k] * scale[k] + offset[k] for k in range(3)) for val in vals]
                attrs[key] = vals
            ib = index_base + _int((ch.get("chunkIndices") or {}).get("teOffset"))
            info["indices_data"] = list(struct.unpack_from(f"<{ni}H", buffer, ib)) if ni else []
            info["attributes"] = attrs
        chunks.append(info)
    appearances = []
    for a in root.get("appearances") or []:
        d = a.get("Data") or {}
        appearances.append({"name": _enum(d.get("name")), "chunk_materials": [_enum(c) for c in d.get("chunkMaterials") or []]})
    bb = root.get("boundingBox") or {}
    return {"chunks": chunks, "appearances": appearances,
            "materials": [_enum(m.get("name")) for m in root.get("materialEntries") or []],
            "external_materials": [_enum(((m.get("DepotPath") or {}))) for m in root.get("externalMaterials") or []],
            "lod_levels": root.get("lodLevelInfo"),
            "bounds": {"min": [float((bb.get("Min") or {}).get(k, 0)) for k in "XYZ"], "max": [float((bb.get("Max") or {}).get(k, 0)) for k in "XYZ"]},
            "buffer_bytes": len(buffer), "vertex_buffer_bytes": _int(header.get("vertexBufferSize")),
            "index_buffer_bytes": _int(header.get("indexBufferSize")), "index_buffer_offset": index_base}


def load_reference(path: str | Path | None) -> dict[str, Any] | None:
    if not path:
        return None
    p = Path(path).expanduser()
    if not p.is_file():
        raise FileNotFoundError(f"reference mesh JSON not found: {p}")
    doc = json.loads(p.read_text(encoding="utf-8"))
    _reference(doc)
    return doc
