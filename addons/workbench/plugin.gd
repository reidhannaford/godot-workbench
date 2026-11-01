@tool
extends EditorPlugin
## Adds a Workbench toggle and its options menu to the 3D editor toolbar, and a
## shortcut (workbench/toggle, Alt+Z by default) to flip it, and others for
## x-ray (workbench/toggle_xray, Alt+Shift+Z) and wireframe
## (workbench/toggle_wireframe, Alt+Shift+W).

const WorkbenchController := preload("workbench_controller.gd")
const WorkbenchSettings := preload("workbench_settings.gd")
const WorkbenchEffect := preload("workbench_effect.gd")

const SHORTCUT_PATH := "workbench/toggle"
const XRAY_SHORTCUT_PATH := "workbench/toggle_xray"
const WIREFRAME_SHORTCUT_PATH := "workbench/toggle_wireframe"

enum Item { STUDIO, MATCAP, FLAT, TEXTURE, CAVITY, OUTLINE, CHOOSE_MATCAP, XRAY, CREASE, WIREFRAME, WIREFRAME_OPTIONS }
## Ids of the bundled matcaps in their submenu: this plus their index.
const MATCAP_ID_BASE := 100

var _controller: WorkbenchController
var _settings: WorkbenchSettings
var _bar: HBoxContainer
var _toggle: Button
var _menu: MenuButton
var _matcap_menu: PopupMenu
var _file_dialog: EditorFileDialog
## The Wireframe Options… panel: opacity and angle threshold sliders, like
## the ones in Blender's overlay popover. A PopupMenu can't hold sliders.
var _wireframe_panel: PopupPanel
var _opacity_slider: HSlider
var _threshold_slider: HSlider
## True while [method _save_settings] writes: EditorSettings emits
## settings_changed from inside each set_setting, and reloading the settings
## half-way through a save would overwrite the values not yet written.
var _saving: bool = false


func _enter_tree() -> void:
	_register_shortcuts()
	_settings = WorkbenchSettings.new()
	_settings.load()
	_controller = WorkbenchController.new()
	_apply_settings()

	_bar = HBoxContainer.new()
	_toggle = Button.new()
	_toggle.name = "WorkbenchToggle"
	_toggle.text = "Workbench"
	_toggle.toggle_mode = true
	_toggle.flat = true
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.icon = EditorInterface.get_editor_theme().get_icon(&"SphereMesh", &"EditorIcons")
	_toggle.toggled.connect(_on_toggled)
	_bar.add_child(_toggle)
	_menu = MenuButton.new()
	_menu.name = "WorkbenchMenu"
	_menu.flat = true
	_menu.focus_mode = Control.FOCUS_NONE
	_menu.icon = EditorInterface.get_editor_theme().get_icon(&"GuiTabMenuHl", &"EditorIcons")
	_menu.tooltip_text = "Workbench options"
	_menu.get_popup().id_pressed.connect(_on_menu_pressed)
	# Ticking an option keeps the menu open, so several can be changed in one
	# go; only "Choose MatCap…" and the like close it.
	_menu.get_popup().hide_on_checkable_item_selection = false
	_bar.add_child(_menu)
	_build_menu()
	_sync_menu()
	_update_tooltip()
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _bar)
	set_input_event_forwarding_always_enabled()
	# Editor Settings > Workbench edits (the outline width, the x-ray
	# opacity) take effect at once.
	EditorInterface.get_editor_settings().settings_changed.connect(_on_settings_changed)


func _exit_tree() -> void:
	var editor_settings := EditorInterface.get_editor_settings()
	if editor_settings.settings_changed.is_connected(_on_settings_changed):
		editor_settings.settings_changed.disconnect(_on_settings_changed)
	if _controller != null:
		_controller.active = false
	if _bar != null:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _bar)
		_bar.free()
	_bar = null
	_toggle = null
	_menu = null
	if _file_dialog != null:
		_file_dialog.queue_free()
	_file_dialog = null
	if _wireframe_panel != null:
		_wireframe_panel.queue_free()
	_wireframe_panel = null
	_opacity_slider = null
	_threshold_slider = null
	_controller = null


func _forward_3d_gui_input(_viewport_camera: Camera3D, event: InputEvent) -> int:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return AFTER_GUI_INPUT_PASS
	var settings := EditorInterface.get_editor_settings()
	if settings.has_shortcut(SHORTCUT_PATH) and settings.get_shortcut(SHORTCUT_PATH).matches_event(event):
		_toggle.button_pressed = not _toggle.button_pressed
		return AFTER_GUI_INPUT_STOP
	if settings.has_shortcut(XRAY_SHORTCUT_PATH) and settings.get_shortcut(XRAY_SHORTCUT_PATH).matches_event(event):
		_on_menu_pressed(Item.XRAY)
		if _settings.xray and not _toggle.button_pressed:
			_toggle.button_pressed = true
		return AFTER_GUI_INPUT_STOP
	if settings.has_shortcut(WIREFRAME_SHORTCUT_PATH) and settings.get_shortcut(WIREFRAME_SHORTCUT_PATH).matches_event(event):
		_on_menu_pressed(Item.WIREFRAME)
		if _settings.wireframe and not _toggle.button_pressed:
			_toggle.button_pressed = true
		return AFTER_GUI_INPUT_STOP
	return AFTER_GUI_INPUT_PASS


func _register_shortcuts() -> void:
	_register_shortcut(SHORTCUT_PATH, "Toggle Workbench", KEY_Z, false)
	_register_shortcut(XRAY_SHORTCUT_PATH, "Toggle Workbench X-Ray", KEY_Z, true)
	# Blender's Shift+Z is the editor's "lock to XY plane"; W is free with Alt+Shift.
	_register_shortcut(WIREFRAME_SHORTCUT_PATH, "Toggle Workbench Wireframe", KEY_W, true)


func _register_shortcut(path: String, label: String, keycode: Key, shift: bool) -> void:
	var settings := EditorInterface.get_editor_settings()
	if settings.has_shortcut(path):
		return
	var key := InputEventKey.new()
	key.keycode = keycode
	key.alt_pressed = true
	key.shift_pressed = shift
	var shortcut := Shortcut.new()
	shortcut.resource_name = label
	shortcut.events = [key]
	settings.add_shortcut(path, shortcut)


func _apply_settings() -> void:
	var effect := _controller.effect
	effect.shading = _settings.shading as WorkbenchEffect.Shading
	effect.cavity = 1.0 if _settings.cavity else 0.0
	effect.outline = 1.0 if _settings.outline else 0.0
	# The width is in points; the viewport has editor-scale pixels per point.
	effect.outline_width = _settings.outline_width * EditorInterface.get_editor_scale()
	effect.crease = _settings.crease
	effect.matcap = _settings.load_matcap()
	_controller.texture_color = _settings.texture_color
	_controller.xray = _settings.xray
	_controller.xray_alpha = _settings.xray_alpha
	_controller.wireframe = _settings.wireframe
	_controller.wireframe_opacity = _settings.wireframe_opacity
	_controller.wireframe_threshold = _settings.wireframe_threshold


func _on_settings_changed() -> void:
	if _saving or _settings == null or _controller == null or _menu == null:
		return
	_settings.load()
	_apply_settings()
	_sync_menu()
	_sync_wireframe_panel()
	_update_tooltip()


func _on_toggled(on: bool) -> void:
	_controller.active = on


func _build_menu() -> void:
	var popup := _menu.get_popup()
	popup.add_radio_check_item("Studio Lighting", Item.STUDIO)
	popup.add_radio_check_item("MatCap", Item.MATCAP)
	popup.add_separator()
	popup.add_radio_check_item("Flat Colour", Item.FLAT)
	popup.add_radio_check_item("Texture Colour", Item.TEXTURE)
	popup.add_separator()
	popup.add_check_item("Cavity", Item.CAVITY)
	popup.add_check_item("Outline", Item.OUTLINE)
	popup.add_check_item("Crease Lines", Item.CREASE)
	popup.add_check_item("Wireframe", Item.WIREFRAME)
	popup.add_item("Wireframe Options…", Item.WIREFRAME_OPTIONS)
	popup.add_separator()
	popup.add_check_item("X-Ray", Item.XRAY)
	popup.add_separator()
	_matcap_menu = PopupMenu.new()
	_matcap_menu.name = "WorkbenchMatcaps"
	_matcap_menu.hide_on_checkable_item_selection = false
	var index := 0
	for label: String in WorkbenchSettings.BUNDLED_MATCAPS:
		_matcap_menu.add_radio_check_item(label, MATCAP_ID_BASE + index)
		index += 1
	_matcap_menu.id_pressed.connect(_on_matcap_menu_pressed)
	popup.add_submenu_node_item("Bundled MatCaps", _matcap_menu)
	popup.add_item("Choose MatCap…", Item.CHOOSE_MATCAP)


## Shows the current settings on the menu items; the menu may be open.
func _sync_menu() -> void:
	var popup := _menu.get_popup()
	popup.set_item_checked(popup.get_item_index(Item.STUDIO), _settings.shading == WorkbenchEffect.Shading.STUDIO)
	popup.set_item_checked(popup.get_item_index(Item.MATCAP), _settings.shading == WorkbenchEffect.Shading.MATCAP)
	popup.set_item_checked(popup.get_item_index(Item.FLAT), not _settings.texture_color)
	popup.set_item_checked(popup.get_item_index(Item.TEXTURE), _settings.texture_color)
	popup.set_item_checked(popup.get_item_index(Item.CAVITY), _settings.cavity)
	popup.set_item_checked(popup.get_item_index(Item.OUTLINE), _settings.outline)
	popup.set_item_checked(popup.get_item_index(Item.CREASE), _settings.crease)
	popup.set_item_disabled(popup.get_item_index(Item.CREASE), not _settings.outline)
	popup.set_item_checked(popup.get_item_index(Item.WIREFRAME), _settings.wireframe)
	popup.set_item_checked(popup.get_item_index(Item.XRAY), _settings.xray)
	var index := 0
	for label: String in WorkbenchSettings.BUNDLED_MATCAPS:
		_matcap_menu.set_item_checked(_matcap_menu.get_item_index(MATCAP_ID_BASE + index), _settings.matcap_path == WorkbenchSettings.BUNDLED_MATCAPS[label])
		index += 1


func _on_menu_pressed(id: int) -> void:
	match id:
		Item.STUDIO:
			_settings.shading = WorkbenchEffect.Shading.STUDIO
		Item.MATCAP:
			_settings.shading = WorkbenchEffect.Shading.MATCAP
		Item.FLAT:
			_settings.texture_color = false
		Item.TEXTURE:
			_settings.texture_color = true
		Item.CAVITY:
			_settings.cavity = not _settings.cavity
		Item.OUTLINE:
			_settings.outline = not _settings.outline
		Item.CREASE:
			_settings.crease = not _settings.crease
		Item.XRAY:
			_settings.xray = not _settings.xray
		Item.WIREFRAME:
			_settings.wireframe = not _settings.wireframe
		Item.CHOOSE_MATCAP:
			_choose_matcap()
			return
		Item.WIREFRAME_OPTIONS:
			_show_wireframe_options()
			return
	_save_settings()
	_apply_settings()
	_sync_menu()
	_update_tooltip()


func _on_matcap_menu_pressed(id: int) -> void:
	var labels := WorkbenchSettings.BUNDLED_MATCAPS.keys()
	var index := id - MATCAP_ID_BASE
	if index < 0 or index >= labels.size():
		return
	_settings.matcap_path = WorkbenchSettings.BUNDLED_MATCAPS[labels[index] as String]
	_settings.shading = WorkbenchEffect.Shading.MATCAP
	_save_settings()
	_apply_settings()
	_sync_menu()
	_update_tooltip()


## Writes the settings without the editor's settings_changed reloading them
## half-way through.
func _save_settings() -> void:
	_saving = true
	_settings.save()
	_saving = false


## Opens the slider panel under the options menu.
func _show_wireframe_options() -> void:
	if _wireframe_panel == null:
		_wireframe_panel = PopupPanel.new()
		_wireframe_panel.name = "WorkbenchWireframeOptions"
		var box := VBoxContainer.new()
		_wireframe_panel.add_child(box)
		_opacity_slider = _add_slider(box, "Opacity", 0.1, 1.0, 0.05, _on_opacity_slider)
		_threshold_slider = _add_slider(box, "Threshold", 0.0, 90.0, 1.0, _on_threshold_slider, "°")
		_threshold_slider.tooltip_text = "Only line the edges where the surfaces either side meet at this angle or more. 0 lines every edge, and hides nothing."
		EditorInterface.get_base_control().add_child(_wireframe_panel)
	_sync_wireframe_panel()
	var scale := EditorInterface.get_editor_scale()
	var position := Vector2i(_menu.get_screen_position() + Vector2(0.0, _menu.size.y))
	_wireframe_panel.popup(Rect2i(position, Vector2i(Vector2(280.0, 0.0) * scale)))


## A labelled slider row with its value shown beside it; [param changed]
## gets the new value.
func _add_slider(box: VBoxContainer, label: String, minimum: float, maximum: float, step: float, changed: Callable, suffix: String = "") -> HSlider:
	var scale := EditorInterface.get_editor_scale()
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = label
	name_label.custom_minimum_size.x = 72.0 * scale
	row.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_NONE
	row.add_child(slider)
	var value_label := Label.new()
	value_label.custom_minimum_size.x = 40.0 * scale
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	var show_value := func(value: float) -> void:
		value_label.text = ("%d%s" % [int(round(value)), suffix]) if step >= 1.0 else ("%.2f%s" % [value, suffix])
	slider.value_changed.connect(show_value)
	slider.value_changed.connect(changed)
	slider.set_meta(&"show_value", show_value)
	box.add_child(row)
	return slider


## Puts the settings on the sliders without their signals writing them back.
func _sync_wireframe_panel() -> void:
	if _wireframe_panel == null:
		return
	for pair: Array in [[_opacity_slider, _settings.wireframe_opacity], [_threshold_slider, _settings.wireframe_threshold]]:
		var slider := pair[0] as HSlider
		slider.set_value_no_signal(pair[1] as float)
		(slider.get_meta(&"show_value") as Callable).call(slider.value)


func _on_opacity_slider(value: float) -> void:
	_settings.wireframe_opacity = value
	_save_settings()
	_apply_settings()


func _on_threshold_slider(value: float) -> void:
	_settings.wireframe_threshold = value
	_save_settings()
	_apply_settings()


func _choose_matcap() -> void:
	if _file_dialog == null:
		_file_dialog = EditorFileDialog.new()
		_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
		_file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
		_file_dialog.title = "Choose a MatCap image"
		_file_dialog.add_filter("*.png, *.jpg, *.jpeg, *.exr, *.webp", "Images")
		_file_dialog.file_selected.connect(_on_matcap_chosen)
		EditorInterface.get_base_control().add_child(_file_dialog)
	_file_dialog.current_path = _settings.matcap_path
	_file_dialog.popup_file_dialog()


func _on_matcap_chosen(path: String) -> void:
	_settings.matcap_path = path
	_settings.shading = WorkbenchEffect.Shading.MATCAP
	_save_settings()
	_apply_settings()
	_sync_menu()
	_update_tooltip()


func _update_tooltip() -> void:
	var shortcut_text := ""
	var settings := EditorInterface.get_editor_settings()
	if settings.has_shortcut(SHORTCUT_PATH):
		shortcut_text = " (%s)" % settings.get_shortcut(SHORTCUT_PATH).get_as_text()
	var mode := "MatCap: %s" % _settings.matcap_path.get_file() if _settings.shading == WorkbenchEffect.Shading.MATCAP else "Studio lighting"
	var xray_text := ""
	if settings.has_shortcut(XRAY_SHORTCUT_PATH):
		xray_text = "\nX-ray: %s (%s)." % ["on" if _settings.xray else "off", settings.get_shortcut(XRAY_SHORTCUT_PATH).get_as_text()]
	var wireframe_text := ""
	if settings.has_shortcut(WIREFRAME_SHORTCUT_PATH):
		wireframe_text = "\nWireframe: %s (%s)." % ["on" if _settings.wireframe else "off", settings.get_shortcut(WIREFRAME_SHORTCUT_PATH).get_as_text()]
	_toggle.tooltip_text = "Workbench%s\n%s, %s colour.%s%s" % [shortcut_text, mode, "texture" if _settings.texture_color else "flat", xray_text, wireframe_text]
