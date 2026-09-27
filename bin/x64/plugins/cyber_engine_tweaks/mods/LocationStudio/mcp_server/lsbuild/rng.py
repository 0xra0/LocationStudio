"""Seed normalization and Park-Miller samples shared by MCP documentation/tests."""
from __future__ import annotations

import secrets
from typing import Any


def create(seed: int | None = None, sample_count: int = 8) -> dict[str, Any]:
    if sample_count < 0 or sample_count > 64:
        raise ValueError("sample_count must be between 0 and 64")
    normalized = secrets.randbelow(2147483646) + 1 if seed is None else abs(int(seed)) % 2147483647
    if normalized == 0:
        normalized = 1
    state = normalized
    samples = []
    for _ in range(sample_count):
        state = (state * 48271) % 2147483647
        samples.append(state / 2147483647)
    return {"seed": normalized, "algorithm": "Park-Miller 48271 modulo 2147483647",
            "samples": samples, "sample_count": sample_count,
            "usage": "Pass seed to wb_polygon_scatter, wb_volume_scatter, or wb_live_surface_scatter."}
