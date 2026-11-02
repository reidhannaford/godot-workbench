extends SceneTree
## Headless check that the plugin loads, puts its toggle in the 3D toolbar,
## and that the controller takes over the editor viewports only for a draw
## and restores them.
## Run: godot --headless --editor --path . -s res://test/plugin_test.gd

const WorkbenchController := preload("res://addons/workbench/workbench_controller.gd")
const WorkbenchSettings := preload("res://addons/workbench/workbench_settings.gd")
const WorkbenchEffect := preload("res://addons/workbench/workbench_effect.gd")
const WorkbenchUpdater := preload("res://addons/workbench/workbench_updater.gd")

var _failures: int = 0


func _initialize() -> void:
	var watchdog := create_timer(30.0)
	watchdog.timeout.connect(func() -> void:
		print("WATCHDOG: test did not finish")
		quit(2))
	_run()


func _run() -> void:
	await process_frame
	await process_frame

	var viewport := EditorInterface.get_editor_viewport_3d(0)
	var camera := viewport.get_camera_3d()
	_check(camera != null, "the editor viewport has a camera")
	var msaa_before := viewport.msaa_3d
	var env_before := camera.environment
	var attributes_before := camera.attributes
	var debug_draw_before := viewport.debug_draw
	var children_before := viewport.get_child_count()

	var controller := WorkbenchController.new()
	controller.active = true
	_check(viewport.msaa_3d == Viewport.MSAA_DISABLED, "MSAA is off while active")
	_check(camera.environment == env_before, "between frames the camera keeps the editor's environment")
	_check(camera.compositor == null, "between frames the camera has no compositor")
	_check(RenderingServer.frame_pre_draw.is_connected(controller.before_draw), "before_draw is hooked to frame_pre_draw")
	_check(RenderingServer.frame_post_draw.is_connected(controller.after_draw), "after_draw is hooked to frame_post_draw")

	controller.before_draw()
	_check(camera.environment == controller.environment, "the draw gets the solid environment")
	_check(camera.attributes == controller.attributes, "the draw gets neutral camera attributes")
	_check(camera.compositor != null and camera.compositor.compositor_effects.size() == 1, "the draw gets a compositor with the effect")
	_check(viewport.debug_draw == Viewport.DEBUG_DRAW_DISABLED, "flat colour draws normally")
	_check(viewport.get_child_count() == children_before, "no x-ray viewport while x-ray is off")
	controller.after_draw()
	_check(camera.environment == env_before, "after the draw the environment is the editor's again")
	_check(camera.attributes == attributes_before, "after the draw the attributes are the editor's again")
	_check(camera.compositor == null, "after the draw the compositor is gone")
	_check(viewport.debug_draw == debug_draw_before, "after the draw the debug draw is the editor's again")

	viewport.msaa_3d = Viewport.MSAA_4X
	controller.texture_color = true
	controller.before_draw()
	_check(viewport.msaa_3d == Viewport.MSAA_DISABLED, "before_draw puts MSAA off again after the editor resets it")
	_check(viewport.debug_draw == Viewport.DEBUG_DRAW_UNSHADED, "texture colour draws unshaded")
	controller.after_draw()
	_check(viewport.debug_draw == debug_draw_before, "debug draw restored after an unshaded draw")

	controller.xray = true
	controller.before_draw()
	var ghost := viewport.find_child(WorkbenchController.XRAY_VIEWPORT_NAME, false, false) as SubViewport
	_check(ghost != null, "x-ray adds a hidden viewport under the editor viewport")
	if ghost != null:
		_check(ghost.debug_draw == Viewport.DEBUG_DRAW_OVERDRAW, "the hidden viewport draws overdraw")
		_check(ghost.size == viewport.size, "the hidden viewport matches the editor viewport's size")
		var ghost_camera := ghost.get_camera_3d()
		_check(ghost_camera != null, "the hidden viewport has a camera")
		if ghost_camera != null:
			_check(ghost_camera.global_transform.is_equal_approx(camera.global_transform), "the hidden camera copies the editor camera")
			_check(ghost_camera.cull_mask & ~WorkbenchController.GAME_LAYERS == 0, "the hidden camera leaves out the gizmo layers")
			_check(ghost_camera.environment == controller.environment, "the hidden camera has the neutral environment")
		var own_effect := camera.compositor.compositor_effects[0] as WorkbenchEffect
		_check(own_effect.xray > 0.0, "the effect gets the x-ray opacity")
		_check(own_effect.outline_width >= 1.0, "the effect gets an outline width of at least a pixel")
		_check(own_effect.xray_texture == RenderingServer.viewport_get_texture(ghost.get_viewport_rid()), "the effect gets the hidden viewport's texture")
	controller.after_draw()
	controller.xray = false
	controller.before_draw()
	_check(ghost == null or ghost.is_queued_for_deletion(), "turning x-ray off removes the hidden viewport")
	controller.after_draw()

	controller.wireframe = true
	controller.before_draw()
	var wire := viewport.find_child(WorkbenchController.WIREFRAME_VIEWPORT_NAME, false, false) as SubViewport
	_check(wire != null, "wireframe adds a hidden viewport under the editor viewport")
	if wire != null:
		_check(wire.debug_draw == Viewport.DEBUG_DRAW_WIREFRAME, "the hidden viewport draws wireframe")
		_check(wire.use_hdr_2d, "the hidden wireframe viewport renders in HDR")
		var wire_camera := wire.get_camera_3d()
		_check(wire_camera != null, "the hidden wireframe viewport has a camera")
		if wire_camera != null:
			_check(wire_camera.global_transform.is_equal_approx(camera.global_transform), "the hidden wireframe camera copies the editor camera")
			_check(wire_camera.cull_mask & ~WorkbenchController.GAME_LAYERS == 0, "the hidden wireframe camera leaves out the gizmo layers")
			var export_effect: WorkbenchEffect = null
			if wire_camera.compositor != null and wire_camera.compositor.compositor_effects.size() == 1:
				export_effect = wire_camera.compositor.compositor_effects[0] as WorkbenchEffect
			_check(export_effect != null, "the hidden wireframe camera has a compositor with one effect")
			if export_effect != null:
				_check(export_effect.depth_export, "that effect exports depth")
				_check(not export_effect.needs_normal_roughness, "the depth export doesn't ask for the normal buffer")
		var own_effect := camera.compositor.compositor_effects[0] as WorkbenchEffect
		_check(own_effect.wireframe > 0.0, "the effect gets the wireframe opacity")
		_check(own_effect.wireframe_texture == RenderingServer.viewport_get_texture(wire.get_viewport_rid()), "the effect gets the wireframe viewport's texture")
		_check(viewport.find_child(WorkbenchController.XRAY_VIEWPORT_NAME, false, false) == null or (viewport.find_child(WorkbenchController.XRAY_VIEWPORT_NAME, false, false) as Node).is_queued_for_deletion(), "wireframe alone adds no x-ray viewport")
	controller.after_draw()
	controller.wireframe = false
	controller.before_draw()
	_check(wire == null or wire.is_queued_for_deletion(), "turning wireframe off removes the hidden viewport")
	controller.after_draw()

	controller.before_draw()
	controller.active = false
	_check(camera.environment == env_before, "deactivating mid-draw restores the environment")
	_check(camera.compositor == null, "deactivating removes the compositor")
	_check(viewport.msaa_3d == msaa_before, "MSAA restored")
	_check(not RenderingServer.frame_pre_draw.is_connected(controller.before_draw), "before_draw is unhooked")
	_check(not RenderingServer.frame_post_draw.is_connected(controller.after_draw), "after_draw is unhooked")
	await process_frame
	_check(viewport.get_child_count() == children_before, "the editor viewport has no leftover children")

	var toggle := EditorInterface.get_base_control().find_child("WorkbenchToggle", true, false) as Button
	_check(toggle != null, "the Workbench toggle is in the 3D toolbar")
	if toggle != null:
		toggle.button_pressed = true
		await process_frame
		_check(viewport.msaa_3d == Viewport.MSAA_DISABLED, "the toggle turns workbench on")
		_check(camera.environment == env_before, "the toggle leaves the editor's environment alone between frames")
		toggle.button_pressed = false
		await process_frame
		_check(viewport.msaa_3d == msaa_before, "the toggle turns it off again")

	for label: String in WorkbenchSettings.BUNDLED_MATCAPS:
		var path: String = WorkbenchSettings.BUNDLED_MATCAPS[label]
		_check(ResourceLoader.exists(path), "bundled matcap %s exists at %s" % [label, path])
	var matcap_menu := EditorInterface.get_base_control().find_child("WorkbenchMatcaps", true, false) as PopupMenu
	_check(matcap_menu != null and matcap_menu.item_count == WorkbenchSettings.BUNDLED_MATCAPS.size(), "the Bundled MatCaps submenu lists every bundled matcap")

	var settings := EditorInterface.get_editor_settings()
	_check(settings.has_shortcut("workbench/toggle"), "the shortcut is registered")
	_check(settings.has_shortcut("workbench/toggle_xray"), "the x-ray shortcut is registered")
	_check(settings.has_shortcut("workbench/toggle_wireframe"), "the wireframe shortcut is registered")
	_check(settings.has_setting("workbench/wireframe") and settings.has_setting("workbench/wireframe_opacity") and settings.has_setting("workbench/wireframe_threshold"), "the wireframe settings are registered")
	var menu := EditorInterface.get_base_control().find_child("WorkbenchMenu", true, false) as MenuButton
	_check(menu != null and menu.get_popup().get_item_index(9) >= 0 and menu.get_popup().get_item_text(menu.get_popup().get_item_index(9)) == "Wireframe", "the options menu has a Wireframe item")
	if menu != null:
		var popup := menu.get_popup()
		_check(popup.get_item_index(10) >= 0 and popup.get_item_text(popup.get_item_index(10)) == "Wireframe Options…", "the options menu has a Wireframe Options… item")
		popup.id_pressed.emit(10)
		await process_frame
		var panel := EditorInterface.get_base_control().find_child("WorkbenchWireframeOptions", true, false) as PopupPanel
		_check(panel != null, "Wireframe Options… opens a panel")
		if panel != null:
			var sliders := panel.find_children("*", "HSlider", true, false)
			_check(sliders.size() == 2, "the panel has two sliders")
			if sliders.size() == 2:
				var opacity_slider := sliders[0] as HSlider
				var threshold_slider := sliders[1] as HSlider
				_check(is_equal_approx(opacity_slider.value, settings.get_setting("workbench/wireframe_opacity")), "the opacity slider shows the setting")
				threshold_slider.value = 30.0
				_check(is_equal_approx(settings.get_setting("workbench/wireframe_threshold"), 30.0), "moving the threshold slider writes the setting")
				settings.set_setting("workbench/wireframe_threshold", 45.0)
				await process_frame
				_check(is_equal_approx(threshold_slider.value, 45.0), "an Editor Settings edit moves the slider")
				settings.set_setting("workbench/wireframe_threshold", 0.0)
				settings.set_setting("workbench/matcap", "res://addons/workbench/matcaps/normal.png")
				settings.set_setting("workbench/shading", 0)
				await process_frame
				var submenu := EditorInterface.get_base_control().find_child("WorkbenchMatcaps", true, false) as PopupMenu
				submenu.id_pressed.emit(100)
				_check(settings.get_setting("workbench/matcap") == "res://addons/workbench/matcaps/clay.png" and settings.get_setting("workbench/shading") == 1, "picking a matcap while in studio lighting keeps both the matcap and the shading")
			panel.hide()
		_check(popup.get_item_index(11) >= 0 and popup.get_item_text(popup.get_item_index(11)) == "Check for Updates…", "the options menu has a Check for Updates… item")
		_check(popup.get_item_index(12) >= 0 and popup.get_item_text(popup.get_item_index(12)) == "About Workbench…", "the options menu has an About Workbench… item")
		popup.id_pressed.emit(12)
		await process_frame
		var about := EditorInterface.get_base_control().find_child("WorkbenchAbout", true, false) as AcceptDialog
		_check(about != null and about.visible, "About Workbench… opens a dialog")
		if about != null:
			var labels := about.find_children("*", "RichTextLabel", true, false)
			_check(labels.size() == 1 and (labels[0] as RichTextLabel).text.contains("github.com/reidhannaford/godot-workbench"), "the About dialog links to the repository")
			about.hide()

	_check(settings.has_setting("workbench/check_for_updates"), "the check_for_updates setting is registered")
	var updater := EditorInterface.get_base_control().find_child("WorkbenchUpdater", true, false) as WorkbenchUpdater
	_check(updater != null, "the updater is under the base control")
	if updater != null:
		var config := ConfigFile.new()
		config.load("res://addons/workbench/plugin.cfg")
		_check(updater.current_version == str(config.get_value("plugin", "version", "")), "the updater reads the version from plugin.cfg")
		_check(not updater.has_update() and not updater.is_busy(), "headless, the updater has not checked")
	_check(WorkbenchUpdater.compare_versions("1.3.1", "1.3.0") > 0, "1.3.1 is newer than 1.3.0")
	_check(WorkbenchUpdater.compare_versions("v1.4", "1.4.0") == 0, "v1.4 is 1.4.0")
	_check(WorkbenchUpdater.compare_versions("1.9.9", "2.0") < 0, "1.9.9 is older than 2.0")
	_check(WorkbenchUpdater.compare_versions("1.10.0", "1.9.0") > 0, "versions compare by number, not by text")

	print("FAILURES %d" % _failures)
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, what: String) -> void:
	if condition:
		print("PASS %s" % what)
	else:
		_failures += 1
		print("FAIL %s" % what)
