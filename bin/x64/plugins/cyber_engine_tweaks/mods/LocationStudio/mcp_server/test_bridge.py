#!/usr/bin/env python3
import json
import re
from pathlib import Path


def test_project_shape() -> None:
    # Source/upgrade packages intentionally do not ship a user project.json.
    # Validate schema/default collections from the model implementation instead
    # of requiring mutable runtime data in the source tree.
    mod = Path(__file__).resolve().parents[1]
    model = (mod / 'modules' / 'model.lua').read_text(encoding='utf-8')
    assert 'schema_version=21' in model
    for collection in ('locations', 'routes', 'premises', 'rooms', 'objects', 'object_groups', 'object_prefabs', 'volumes', 'cameras', 'assets', 'room_frames', 'environments', 'splines', 'timelines', 'reference_areas', 'edl_builds'):
        assert re.search(rf'\b{collection}\s*=\s*\{{\}}', model), collection
    for layer in ('shell', 'gameplay', 'decoration', 'lighting', 'quest', 'npc', 'audio', 'debug'):
        assert layer in model
    for setting in ('shell_templates', 'snapping', 'visuals', 'workspace', 'quickstart', 'ent_tools'):
        assert setting in model


def test_mcp_operations_are_handled() -> None:
    mod = Path(__file__).resolve().parents[1]
    server = (mod / 'mcp_server' / 'server.py').read_text(encoding='utf-8')
    bridge = (mod / 'modules' / 'bridge.lua').read_text(encoding='utf-8')
    sent = set(re.findall(r'_send\("([a-z_]+)"', server))
    handled = set(re.findall(r"op == '([a-z_]+)'", bridge))
    handled.update(re.findall(r"or op == '([a-z_]+)'", bridge))
    handled.update(re.findall(r"'((?:wb_)?(?:clipcheck|fixturecheck|fitcheck))'", bridge))
    assert sent <= handled, f'MCP operations missing in CET bridge: {sorted(sent - handled)}'
    assert len(re.findall(r'@mcp\.tool\(\)', server)) == 480
    for operation in ('register_asset', 'update_asset', 'delete_asset', 'place_asset', 'clear_debug_log', 'run_diagnostics',
                      'capture_camera', 'copy_transform', 'paste_transform', 'move_item_to_aim',
                      'drop_item_to_ground', 'aim_item_at_target', 'scatter_at_aim',
                      'detach_shell_piece', 'replace_shell_piece', 'set_construction_state', 'focus_world_builder_object',
                      'get_object_selection', 'set_object_selection', 'transform_object_group',
                      'set_object_group_state', 'spawn_object_group', 'duplicate_object_group', 'delete_object_group',
                      'list_object_groups', 'create_object_group', 'update_object_group', 'select_object_group',
                      'transform_saved_group', 'dissolve_object_group', 'list_object_prefabs',
                      'save_object_prefab', 'instantiate_object_prefab', 'delete_object_prefab',
                      'layout_object_group', 'wb_align', 'wb_distribute', 'wb_path_array', 'wb_radial_array', 'wb_grid', 'replace_object_group_asset', 'pick_aimed_object',
                      'preview_asset', 'stamp_preview', 'clear_asset_preview',
                      'start_transform_grab', 'configure_transform_grab', 'get_transform_grab_status',
                      'commit_transform_grab', 'cancel_transform_grab', 'start_transform_edit',
                      'start_duplicate_transform_edit', 'start_placement_transform_edit',
                      'start_pattern_transform_edit', 'start_mirror_transform_edit', 'start_scatter_transform_edit',
                      'adjust_transform_edit', 'reset_transform_edit', 'get_transform_session_status',
                      'commit_transform_edit', 'cancel_transform_edit',
                      'rht_status', 'rht_crosshair', 'rht_scan', 'rht_node', 'reload_runtime', 'walkability_check',
                      'create_static_light', 'update_static_light', 'preview_time_of_day', 'restore_time_of_day',
                      'mesh_appearance_list', 'mesh_appearance_preview', 'mesh_appearance_apply', 'mesh_appearance_cancel', 'create_decal',
                      'create_interactable', 'list_interactables', 'update_interactable', 'delete_interactable',
                      'vanilla_removal_status', 'remove_vanilla_crosshair', 'remove_vanilla_nearby',
                      'restore_vanilla_removal', 'restore_all_vanilla_removals', 'list_vanilla_removals',
                      'npc_play_anim', 'npc_stop_anim', 'npc_stop_all_anims', 'npc_anim_status', 'npc_list',
                      'raycast_batch', 'floor_probe', 'respawn_tagged', 'camera_pitch', 'npc_spawn_record', 'npc_despawn_tag',
                      'build_export_world_builder', 'build_export_status', 'import_world_builder_build',
                      'wb_bounds_import', 'wb_bounds_info', 'wb_bounds_set', 'wb_bounds_world_aabb', 'wb_bounds_overlap', 'wb_collisions', 'wb_clipcheck', 'wb_fixturecheck', 'wb_fitcheck', 'wb_compat_scan', 'wb_find', 'wb_tree', 'wb_get', 'wb_refs', 'wb_bounds_fit',
                      'wb_frame_create', 'wb_frame_list', 'wb_frame_update', 'wb_frame_delete', 'wb_frame_to_world', 'wb_world_to_frame', 'place_object_in_frame', 'move_object_in_frame',
                      'link_volume_fact',
                      'get_history', 'history_undo', 'history_redo', 'checkpoint_create', 'checkpoint_list', 'checkpoint_diff', 'checkpoint_restore', 'get_runtime_sync_status', 'sync_runtime', 'import_catalog_asset',
                      'wb_favorite_prepare', 'wb_prefab_render', 'wb_prefab_render_status',
                      'wb_generate_cable', 'wb_generate_fence', 'wb_generate_road', 'wb_generate_market', 'wb_generate_noderef',
                      'vfx_categories', 'vfx_search', 'vfx_create', 'vfx_update', 'vfx_list', 'vfx_preview',
                      'vfx_preview_status', 'vfx_preview_commit', 'vfx_preview_clear',
                      'environment_weather_states', 'environment_list', 'environment_create', 'environment_update',
                      'environment_delete', 'environment_preview', 'environment_force', 'environment_status', 'environment_restore',
                      'screenshot_mode_capabilities', 'screenshot_mode_status', 'screenshot_mode_enter', 'screenshot_mode_freeze',
                      'screenshot_mode_unfreeze', 'screenshot_mode_ready', 'screenshot_mode_reset_ready', 'screenshot_mode_restore',
                      'collision_presets', 'collision_create_primitive', 'collision_search_meshes', 'collision_import_mesh',
                      'collision_fit_to_object', 'collision_update', 'collision_list', 'collision_layers',
                      'collision_visualization', 'collision_passability',
                      'performance_analyze', 'performance_set_budget', 'performance_select_cluster',
                      'visibility_capabilities', 'visibility_create_occluder', 'visibility_occlude_room',
                      'visibility_update_occluder', 'visibility_list_occluders', 'visibility_pvs', 'visibility_hidden_meshes',
                      'layer_list', 'layer_create', 'layer_update', 'layer_set_visible', 'layer_set_locked', 'layer_isolate',
                      'layer_select_all', 'layer_assign', 'layer_auto_assign', 'layer_delete',
                      'spline_list', 'spline_create', 'spline_update', 'spline_delete', 'spline_add_point', 'spline_insert_point',
                      'spline_update_point', 'spline_delete_point', 'spline_sample', 'spline_apply_use', 'spline_regenerate',
                      'spline_remove_use', 'spline_preview', 'spline_preview_clear',
                      'timeline_list', 'timeline_get', 'timeline_create', 'timeline_update', 'timeline_delete', 'timeline_add_track',
                      'timeline_update_track', 'timeline_delete_track', 'timeline_add_key', 'timeline_update_key', 'timeline_delete_key',
                      'timeline_evaluate', 'timeline_validate', 'timeline_play', 'timeline_seek', 'timeline_pause', 'timeline_stop',
                      'timeline_status', 'timeline_export',
                      'vanilla_clone_status', 'vanilla_clone_pick', 'vanilla_clone_scan', 'vanilla_clone_stage', 'vanilla_clone_candidates',
                      'vanilla_clone_select', 'vanilla_clone_clear', 'vanilla_clone_import', 'vanilla_clone_list', 'vanilla_clone_revert',
                      'reference_area_list', 'reference_area_get', 'reference_area_box', 'reference_area_capture', 'reference_area_show',
                      'reference_area_compare', 'reference_area_copy', 'reference_area_align', 'reference_area_delete'):
        assert operation in sent
    for operation in ('sector_report_load', 'sector_report_flags', 'sector_report_select',
                      'dependency_report_load', 'dependency_report_objects', 'dependency_report_select',
                      'preflight_run', 'preflight_load', 'preflight_select', 'edl_list', 'edl_get', 'edl_remove',
                      'procedural_generators', 'procedural_preview_parts', 'procedural_create', 'procedural_update', 'procedural_delete',
                      'procedural_list', 'procedural_show', 'procedural_settings'):
        assert operation in handled, operation
    for tool in ('performance_export', 'sector_inspect', 'sector_node', 'wb_favorite_add', 'wb_favorites_list', 'wb_device_connect', 'wb_elevator_wire',
                 'wb_polygon_scatter', 'wb_volume_scatter', 'wb_live_surface_scatter', 'wb_rng_create'):
        assert re.search(rf'def {tool}\(', server), tool
    assert re.search(r'def hotcycle_rebuild\(', server)
    assert re.search(r'def visual_regression_capture\(', server)
    assert re.search(r'def visual_regression_accept\(', server)
    assert (mod / 'mcp_server' / 'visual_regression.py').is_file()
    assert 'Pose changes live in the .reds file' in server
    assert 'questforge_world' in (mod / 'modules' / 'storage.lua').read_text(encoding='utf-8')
    assert 'quest_manifest_fragment' in (mod / 'modules' / 'storage.lua').read_text(encoding='utf-8')
    assert (mod.parents[5] / 'QUEST-FORGE-LINKS.md').is_file()
    assert re.search(r'def link_volume_to_quest_fact\(', server)
    for tool in ('create_room_frame', 'list_room_frames', 'update_room_frame', 'delete_room_frame',
                 'room_frame_to_world', 'world_to_room_frame'):
        assert re.search(rf'def {tool}\(', server), tool
    for tool in ('create_project_checkpoint', 'list_project_checkpoints', 'diff_project_checkpoints', 'restore_project_checkpoint', 'get_runtime_sync_status', 'sync_runtime'):
        assert re.search(rf'def {tool}\(', server), tool


def test_v6_modules_are_packaged() -> None:
    mod = Path(__file__).resolve().parents[1]
    for relative in (
        'modules/builder.lua', 'modules/room_kits.lua', 'modules/placement.lua', 'modules/runtime_entities.lua', 'modules/runtime_state.lua', 'modules/vanilla_removal.lua', 'modules/live_tools.lua', 'ui/widgets.lua', 'modules/authoring.lua',
        'modules/markers.lua', 'modules/selection.lua', 'modules/viewport_tools.lua', 'modules/transform_session.lua', 'modules/assemblies.lua', 'modules/actions.lua',
        'modules/logger.lua', 'modules/diagnostics.lua', 'modules/rht_inspector.lua', 'modules/vanilla_removal.lua', 'modules/ent_tools.lua', 'modules/quickstart.lua', 'modules/checkpoints.lua',
        'ui/home.lua', 'ui/premises.lua', 'ui/spatial.lua', 'ui/tools.lua', 'ui/viewport.lua',
        'ui/hierarchy.lua', 'ui/inspector.lua', 'ui/browser.lua'
    ):
        assert (mod / relative).is_file(), relative
    assert (mod / 'mcp_server' / 'collect-debug.sh').is_file()
    assert (mod / 'mcp_server' / 'test_runtime_smoke.py').is_file()
    assert (mod / 'mcp_server' / 'hotcycle.py').is_file()
    assert (mod / 'mcp_server' / 'test_hotcycle.py').is_file()
    assert (mod / 'mcp_server' / 'visual_regression.py').is_file()
    assert (mod / 'mcp_server' / 'test_visual_regression.py').is_file()
    assert (mod / 'mcp_server' / 'test_visual_regression_mcp.py').is_file()
    assert (mod.parents[5] / 'VISUAL-REGRESSION.md').is_file()
    assert (mod / 'logs' / '.keep').is_file()
    assert (mod / 'modules' / 'build_export.lua').is_file()
    assert (mod / 'modules' / 'wb_import.lua').is_file()
    assert (mod / 'modules' / 'asset_bounds.lua').is_file()
    assert (mod / 'modules' / 'prop_validators.lua').is_file()
    assert (mod / 'modules' / 'room_frames.lua').is_file()
    assert (mod / 'modules' / 'project_browser.lua').is_file()
    assert (mod / 'modules' / 'world_builder_generators.lua').is_file()
    assert (mod / 'modules' / 'mesh_appearance.lua').is_file()
    assert (mod / 'modules' / 'vfx.lua').is_file()
    assert (mod / 'modules' / 'environment.lua').is_file()
    assert (mod / 'modules' / 'screenshot_mode.lua').is_file()
    assert (mod / 'modules' / 'collision.lua').is_file()
    assert (mod / 'modules' / 'sector_inspector.lua').is_file()
    assert (mod / 'modules' / 'performance.lua').is_file()
    assert (mod / 'modules' / 'visibility.lua').is_file()
    assert (mod / 'modules' / 'layers.lua').is_file()
    assert (mod / 'modules' / 'splines.lua').is_file()
    assert (mod / 'modules' / 'timeline.lua').is_file()
    assert (mod / 'modules' / 'vanilla_clone.lua').is_file()
    assert (mod / 'modules' / 'reference_areas.lua').is_file()
    assert (mod / 'modules' / 'dependencies.lua').is_file()
    assert (mod / 'modules' / 'preflight.lua').is_file()
    assert (mod / 'mcp_server' / 'lsbuild' / 'edl.py').is_file()
    assert (mod / 'modules' / 'procedural.lua').is_file()
    assert (mod / 'mcp_server' / 'lsbuild' / 'procedural.py').is_file()
    assert (mod / 'mcp_server' / 'lsbuild' / 'meshres.py').is_file()
    assert (mod / 'mcp_server' / 'test_meshres.py').is_file()
    assert (mod.parents[5] / 'MESH-RESOURCES.md').is_file()
    assert (mod / 'mcp_server' / 'test_procedural.py').is_file()
    assert (mod.parents[5] / 'PROCEDURAL-GEOMETRY.md').is_file()
    assert (mod.parents[5] / 'tests' / 'procedural_runtime_test.lua').is_file()
    assert (mod / 'edl' / 'locationstudio-edl-1.schema.json').is_file()
    assert (mod / 'edl' / 'examples' / 'ripperdoc_clinic.edl.yaml').is_file()
    assert (mod / 'mcp_server' / 'test_edl.py').is_file()
    assert (mod.parents[5] / 'ENVIRONMENT-DEFINITION-LANGUAGE.md').is_file()
    assert (mod.parents[5] / 'tests' / 'edl_runtime_test.lua').is_file()
    assert (mod / 'mcp_server' / 'lsbuild' / 'preflight.py').is_file()
    assert (mod / 'mcp_server' / 'test_preflight.py').is_file()
    assert (mod.parents[5] / 'PREFLIGHT.md').is_file()
    assert (mod.parents[5] / 'tests' / 'preflight_runtime_test.lua').is_file()
    assert (mod / 'mcp_server' / 'lsbuild' / 'dependencies.py').is_file()
    assert (mod / 'mcp_server' / 'test_dependencies.py').is_file()
    assert (mod.parents[5] / 'ASSET-DEPENDENCIES.md').is_file()
    assert (mod.parents[5] / 'tests' / 'dependencies_runtime_test.lua').is_file()
    assert (mod / 'mcp_server' / 'test_reference_areas.py').is_file()
    assert (mod.parents[5] / 'REFERENCE-AREAS.md').is_file()
    assert (mod.parents[5] / 'tests' / 'reference_areas_runtime_test.lua').is_file()
    assert (mod / 'mcp_server' / 'lsbuild' / 'vanilla.py').is_file()
    assert (mod / 'mcp_server' / 'test_vanilla_clone.py').is_file()
    assert (mod.parents[5] / 'VANILLA-CLONE.md').is_file()
    assert (mod.parents[5] / 'tests' / 'vanilla_clone_runtime_test.lua').is_file()
    assert (mod / 'mcp_server' / 'test_timeline.py').is_file()
    assert (mod.parents[5] / 'TIMELINE.md').is_file()
    assert (mod.parents[5] / 'tests' / 'timeline_runtime_test.lua').is_file()
    assert (mod / 'mcp_server' / 'test_splines.py').is_file()
    assert (mod.parents[5] / 'SPLINES.md').is_file()
    assert (mod.parents[5] / 'tests' / 'splines_runtime_test.lua').is_file()
    assert (mod / 'mcp_server' / 'test_layers.py').is_file()
    assert (mod.parents[5] / 'LAYERS.md').is_file()
    assert (mod.parents[5] / 'tests' / 'layers_runtime_test.lua').is_file()
    assert (mod / 'mcp_server' / 'test_visibility.py').is_file()
    assert (mod.parents[5] / 'OCCLUSION-VISIBILITY.md').is_file()
    assert (mod.parents[5] / 'tests' / 'visibility_runtime_test.lua').is_file()
    assert (mod / 'mcp_server' / 'lsbuild' / 'performance.py').is_file()
    assert (mod / 'mcp_server' / 'test_performance.py').is_file()
    assert (mod.parents[5] / 'PERFORMANCE-ANALYZER.md').is_file()
    assert (mod.parents[5] / 'tests' / 'performance_runtime_test.lua').is_file()
    assert (mod / 'mcp_server' / 'lsbuild' / 'sectors.py').is_file()
    assert (mod / 'mcp_server' / 'test_sectors.py').is_file()
    assert (mod.parents[5] / 'SECTOR-INSPECTOR.md').is_file()
    assert (mod.parents[5] / 'tests' / 'sector_inspector_runtime_test.lua').is_file()
    assert (mod / 'mcp_server' / 'test_collision.py').is_file()
    assert (mod.parents[5] / 'COLLISION-AUTHORING.md').is_file()
    assert (mod.parents[5] / 'tests' / 'collision_authoring_runtime_test.lua').is_file()
    assert (mod.parents[5] / 'tests' / 'screenshot_mode_runtime_test.lua').is_file()
    assert (mod / 'mcp_server' / 'test_environment.py').is_file()
    assert (mod.parents[5] / 'ENVIRONMENT-PREVIEW.md').is_file()
    assert (mod.parents[5] / 'tests' / 'environment_runtime_test.lua').is_file()
    assert (mod / 'mcp_server' / 'lsbuild' / 'vfx.py').is_file()
    assert (mod / 'mcp_server' / 'test_vfx.py').is_file()
    assert (mod.parents[5] / 'VFX.md').is_file()
    assert (mod.parents[5] / 'tests' / 'vfx_runtime_test.lua').is_file()
    assert (mod.parents[5] / 'MESH-APPEARANCES-AND-DECALS.md').is_file()
    assert (mod / 'mcp_server' / 'wbfavorites.py').is_file()
    assert (mod / 'mcp_server' / 'test_favorites.py').is_file()
    assert (mod / 'mcp_server' / 'test_rng.py').is_file()
    assert (mod / 'mcp_server' / 'mod_inventory.py').is_file()
    assert (mod / 'mcp_server' / 'test_mod_inventory.py').is_file()
    assert (mod.parents[5] / 'tests' / 'project_browser_runtime_test.lua').is_file()
    assert (mod.parents[5] / 'tests' / 'scatter_areas_runtime_test.lua').is_file()
    for relative in ('__init__.py', 'assets.py', 'semantics.py', 'errors.py'):
        assert (mod / 'mcp_server' / 'lsassets' / relative).is_file(), relative
    for relative in ('__init__.py', 'build.py', 'native.py', 'worker.py', 'logs.py', 'wiring.py', 'rng.py', 'LICENSE-cp77wb', 'wkit_worker/Program.cs'):
        assert (mod / 'mcp_server' / 'lsbuild' / relative).is_file(), relative


if __name__ == '__main__':
    test_project_shape()
    test_mcp_operations_are_handled()
    test_v6_modules_are_packaged()
    print('LocationStudio MCP static tests: OK')
