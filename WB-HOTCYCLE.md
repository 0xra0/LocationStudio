# Redscript rebuild and prop hotcycle

LocationStudio v0.35.0 adds the MCP tool `hotcycle_rebuild` and the command-line helper `mcp_server/hotcycle.py`. They deploy rebuilt `.reds` source, wait for RedHotTools to report script reload completion, hot-load optional `.archive` / `.xl` files, then optionally delete tagged dynamic entities and call a scriptable system's sync method.

## Why the script must be included

Some prop poses are authored in redscript. If the pose changed in a `.reds` file but the rebuild cycle skips deploying that file, `SyncProps` runs the old loaded script and respawns the old pose. When requesting respawn, `hotcycle_rebuild` therefore requires `script_files` by default. To knowingly reuse the currently installed script, set `allow_current_script=true`; the result includes an explicit stale-pose warning.

## MCP example

```text
hotcycle_rebuild(
  script_files={"r6/scripts/AshCache/AshCacheGlue.reds": "/work/AshCacheGlue.reds"},
  archives=["/work/ashcache.archive", "/work/ashcache.archive.xl"],
  respawn_tags=["ashcache_counter", "ashcache_chair"],
  system="AshCache.AshCacheGlue",
  method="SyncProps"
)
```

The script destination is relative to the Cyberpunk game root and must be inside `r6/`. Script files are backed up before replacement. Passing a script always asks RedHotTools to compile it, even when its bytes already match the installed file; this covers a previous copy that changed the file while leaving the running script old. RedHotTools reload errors and timeouts stop the cycle before entity respawn. Archives are validated and hot-loaded after the script compile; an incomplete archive load also prevents respawn. Sector re-streaming defaults off, matching the source workflow for dynamic entities; request it only when the archive changes sector nodes that need reloading.

## CLI example

Run from the installed mod's `mcp_server` directory (or pass its path to Python):

```bash
python3 hotcycle.py \
  --script r6/scripts/AshCache/AshCacheGlue.reds=/work/mod/AshCacheGlue.reds \
  --archive /work/mod/ashcache.archive \
  --archive /work/mod/ashcache.archive.xl \
  --respawn-tag ashcache_counter \
  --system AshCache.AshCacheGlue
```

Multiple scripts, archives, and tags can be supplied. Unlike a generic Lua execution endpoint, this workflow accepts bounded file inputs and the redscript system/method name only.
