extends SceneTree
## Opens the test scene in a windowed editor, looking through the scene's own
## Camera3D, and saves screenshots of the viewport with workbench off and in
## each mode, into docs/captures/.
## Run: godot --editor --resolution 1600x900 --path . -s res://tools/capture.gd

const SCENE := "res://test/test_scene.tscn"
const OUT_DIR := "res://docs/captures"
const SETTLE_FRAMES := 40
## How far in front of the camera the editor's orbit pivot is put; any
## distance gives the same view.
const PIVOT_DISTANCE := 4.0


func _initialize() -> void:
	var watchdog := create_timer(120.0)
	watchdog.timeout.connect(func() -> void:
		print("WATCHDOG: capture did not finish")
		quit(2))
	_run()


func _run() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	if not _pin_view_to_camera():
		quit(1)
		return
	EditorInterface.open_scene_from_path(SCENE)
	var waited := 0
	while waited < 600:
		var root_node := EditorInterface.get_edited_scene_root()
		if root_node != null and root_node.scene_file_path == SCENE:
			break
		await process_frame
		waited += 1
	EditorInterface.set_main_screen_editor("3D")
	# The viewport fills the window, so the camera's framing is the image.
	EditorInterface.distraction_free_mode = true
	await _settle()
	_shot("before")

	var base := EditorInterface.get_base_control()
	var toggle := base.find_child("WorkbenchToggle", true, false) as Button
	var menu := base.find_child("WorkbenchMenu", true, false) as MenuButton
	if toggle == null or menu == null:
		print("FAIL: toolbar controls not found")
		quit(1)
		return
	var popup := menu.get_popup()
	# Item ids match plugin.gd's Item enum: 0 studio, 1 matcap, 2 flat,
	# 3 texture, 4 cavity, 5 outline, 7 x-ray, 8 crease lines, 9 wireframe; a
	# bundled matcap is picked by its label in the submenu. Cavity, outline,
	# crease, x-ray and wireframe are toggles and are remembered in editor
	# settings, so they are set to a wanted state.
	var sequence: Array[Array] = [
		["studio", [0, 2], true],
		["studio_texture", [3], true],
		["matcap_normal", [1, 2], true, "Normal"],
		["matcap_contrast", [1, 2], true, "Contrast"],
	]
	toggle.button_pressed = true
	for step: Array in sequence:
		for id: int in step[1] as Array:
			popup.id_pressed.emit(id)
		if step.size() > 3:
			_pick_matcap(popup, step[3] as String)
		_set_checked(popup, 4, step[2] as bool)
		_set_checked(popup, 5, step[2] as bool)
		_set_checked(popup, 8, step[2] as bool)
		await _settle()
		_shot(step[0] as String)
	# Picking a bundled matcap switches to MatCap, so Clay goes back first and
	# studio lighting after it.
	_pick_matcap(popup, "Clay")
	popup.id_pressed.emit(0)
	_set_checked(popup, 7, true)
	await _settle()
	_shot("studio_xray")
	_set_checked(popup, 9, true)
	await _settle()
	_shot("studio_xray_wireframe")
	_set_checked(popup, 7, false)
	await _settle()
	_shot("studio_wireframe")
	# The angle threshold through Editor Settings, which the plugin applies at
	# once: hides the diagonals across the flat faces.
	var editor_settings := EditorInterface.get_editor_settings()
	editor_settings.set_setting("workbench/wireframe_threshold", 30.0)
	await _settle()
	_shot("studio_wireframe_threshold")
	editor_settings.set_setting("workbench/wireframe_threshold", 0.0)
	_set_checked(popup, 9, false)
	_set_view_item("Orthogonal")
	await _settle()
	_shot("studio_ortho")
	_set_view_item("Perspective")
	await _settle()
	toggle.button_pressed = false
	await _settle()
	_shot("after")
	print("DONE")
	quit(0)


## Picks an item of the first editor viewport's view menu by its text, the
## way a click would.
func _set_view_item(text: String) -> void:
	var viewport := EditorInterface.get_editor_viewport_3d(0)
	var editor_viewport := viewport.get_parent().get_parent()
	for child: Node in editor_viewport.find_children("*", "MenuButton", true, false):
		var menu := child as MenuButton
		var view_popup := menu.get_popup()
		for index: int in view_popup.item_count:
			if view_popup.get_item_text(index) == text:
				view_popup.id_pressed.emit(view_popup.get_item_id(index))
				return
	print("FAIL: view menu item %s not found" % text)


## Pins the editor's view to the scene's Camera3D by writing the scene's
## edit-state file, which the editor reads when it opens the scene. The editor
## orbits a pivot, so one is put PIVOT_DISTANCE in front of the camera; roll
## is dropped, since the editor has none. Camera and light gizmos are hidden
## so the camera's own frustum and the lights' lines don't draw across the view.
func _pin_view_to_camera() -> bool:
	var packed := load(SCENE) as PackedScene
	if packed == null:
		print("FAIL: can't load %s" % SCENE)
		return false
	var instance := packed.instantiate()
	var camera: Camera3D = null
	for child: Node in instance.find_children("*", "Camera3D", true, false):
		camera = child as Camera3D
		break
	if camera == null:
		print("FAIL: no Camera3D in %s" % SCENE)
		instance.free()
		return false
	# The editor camera's basis is Ry(-y_rot) * Rx(-x_rot), so its back vector
	# is (-cos x sin y, sin x, cos x cos y).
	# Outside the tree a node has no global transform, so it is composed here.
	var transform := camera.transform
	var parent := camera.get_parent() as Node3D
	while parent != null and parent != instance:
		transform = parent.transform * transform
		parent = parent.get_parent() as Node3D
	var back := transform.basis.z.normalized()
	var x_rot := asin(clampf(back.y, -1.0, 1.0))
	var y_rot := atan2(-back.x, back.z)
	var pivot := transform.origin - back * PIVOT_DISTANCE
	var state := {
		"viewport_mode": 1,
		"fov": camera.fov,
		"gizmos_status": {"Camera3D": 1, "Light3D": 1},
		"viewports": [{
			"distance": PIVOT_DISTANCE,
			"orthogonal": false,
			"position": pivot,
			"x_rotation": x_rot,
			"y_rotation": y_rot,
		}, {}, {}, {}],
	}
	var camera_name := camera.name
	instance.free()
	var config := ConfigFile.new()
	config.set_value("editor_states", "3D", state)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.godot/editor"))
	var path := "res://.godot/editor/%s-editstate-%s.cfg" % [SCENE.get_file(), SCENE.md5_text()]
	var error := config.save(path)
	if error != OK:
		print("FAIL: can't write %s (%s)" % [path, error_string(error)])
		return false
	print("view from %s: pivot %s x %.3f y %.3f fov %.1f" % [camera_name, pivot, x_rot, y_rot, state["fov"]])
	return true


## Picks a bundled matcap by its label in the Bundled MatCaps submenu.
func _pick_matcap(popup: PopupMenu, label: String) -> void:
	var submenu := popup.get_node_or_null("WorkbenchMatcaps") as PopupMenu
	if submenu == null:
		print("FAIL: matcap submenu not found")
		return
	for index: int in submenu.item_count:
		if submenu.get_item_text(index) == label:
			submenu.id_pressed.emit(submenu.get_item_id(index))
			return
	print("FAIL: bundled matcap %s not found" % label)


## Presses a check item only if it isn't already in the wanted state.
func _set_checked(popup: PopupMenu, id: int, wanted: bool) -> void:
	if popup.is_item_checked(popup.get_item_index(id)) != wanted:
		popup.id_pressed.emit(id)


func _settle() -> void:
	for i: int in SETTLE_FRAMES:
		await process_frame


## Saves the whole editor window as name.png and the 3D viewport alone as
## name_view.png, trimmed to a centred 16:9: the editor keeps the camera's
## vertical field of view, so that is the framing of the camera's own preview.
func _shot(name: String) -> void:
	var image := root.get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	var error := image.save_png(path)
	print("shot %s (%s)" % [path, error_string(error)])
	var container := EditorInterface.get_editor_viewport_3d(0).get_parent() as Control
	var scale := float(image.get_width()) / root.size.x
	var rect := container.get_global_rect()
	var region := Rect2i((rect.position * scale).round(), (rect.size * scale).round())
	var wanted_width := int(round(region.size.y * 16.0 / 9.0))
	if wanted_width < region.size.x:
		region.position.x += (region.size.x - wanted_width) / 2
		region.size.x = wanted_width
	else:
		var wanted_height := int(round(region.size.x * 9.0 / 16.0))
		region.position.y += (region.size.y - wanted_height) / 2
		region.size.y = wanted_height
	var view := image.get_region(region)
	var view_path := "%s/%s_view.png" % [OUT_DIR, name]
	error = view.save_png(view_path)
	print("shot %s %s (%s)" % [view_path, view.get_size(), error_string(error)])
