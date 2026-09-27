#!/usr/bin/env python3
"""Deploy a rebuilt redscript/archive and optionally respawn tagged props.

Example:
  python3 hotcycle.py --script r6/scripts/AshCache/AshCacheGlue.reds=/work/mod/AshCacheGlue.reds \
    --archive /work/mod/ashcache.archive --archive /work/mod/ashcache.archive.xl \
    --respawn-tag ashcache_counter --system AshCache.AshCacheGlue

If a prop pose changed in .reds, include that rebuilt script. The tool refuses to
respawn tags from the currently installed script unless --allow-current-script
explicitly acknowledges that the pose may be old.
"""
from __future__ import annotations

import argparse
import json
import sys

import server


def _parse_script(value: str) -> tuple[str, str]:
    if "=" not in value:
        raise argparse.ArgumentTypeError("script must be GAME_RELATIVE_DEST=SOURCE_FILE")
    destination, source = value.split("=", 1)
    if not destination or not source:
        raise argparse.ArgumentTypeError("script must be GAME_RELATIVE_DEST=SOURCE_FILE")
    return destination, source


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--script", action="append", type=_parse_script, default=[], metavar="DEST=SOURCE")
    parser.add_argument("--archive", action="append", default=[])
    parser.add_argument("--respawn-tag", action="append", default=[])
    parser.add_argument("--system", default="")
    parser.add_argument("--method", default="SyncProps")
    parser.add_argument("--restream", action="store_true", help="re-stream sectors after archive reload")
    parser.add_argument("--script-timeout", type=float, default=120.0)
    parser.add_argument("--allow-current-script", action="store_true",
                        help="explicitly permit respawning using the deployed .reds, even if it has the old pose")
    args = parser.parse_args(argv)
    sources = dict(args.script)
    tool = getattr(server.hotcycle_rebuild, "fn", server.hotcycle_rebuild)
    try:
        result = tool(archives=args.archive, script_files=sources, respawn_tags=args.respawn_tag,
                      system=args.system, method=args.method, restream=args.restream,
                      script_timeout_s=args.script_timeout, allow_current_script=args.allow_current_script)
        print(json.dumps(json.loads(result), indent=2))
        return 0
    except Exception as exc:
        print(f"hotcycle failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
