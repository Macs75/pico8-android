extends Control

@onready var container = %VBoxContainer
@onready var close_btn = %ButtonClose

@onready var test_popup = %TestPopup
@onready var test_label = %ResultLabel
@onready var close_test_btn = %CloseTestBtn
var test_device_id: int = -1

func _ready() -> void:
	# Enforce opaque background
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 1.0) # Dark Opaque
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.3, 0.3, 0.3, 1.0)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	add_theme_stylebox_override("panel", style)

	close_btn.pressed.connect(queue_free)
	
	# Connect Test Popup Close Button
	if close_test_btn:
		close_test_btn.pressed.connect(func():
			test_popup.visible = false
			test_device_id = -1
		)
	
	get_tree().root.size_changed.connect(_fit_to_screen)
	_populate_list()
	
	# Initial fit
	call_deferred("_fit_to_screen")

func _populate_list():
	# Clear existing children if any (except template)
	for child in container.get_children():
		if child != %RowTemplate:
			child.queue_free()
		
	# Iterate ALL connected (including user-disabled) but skip system-ignored
	var joypads = Input.get_connected_joypads()
	var visible_count = 0
	
	for device_id in joypads:
		if ControllerUtils.is_system_ignored(device_id):
			continue
			
		visible_count += 1
		var joy_name = Input.get_joy_name(device_id).to_lower()
		var display_name = joy_name
		if display_name.length() > 20:
			display_name = display_name.left(20) + "..."
			
		var row = %RowTemplate.duplicate()
		row.visible = true
		
		# Setup Label
		var label = row.get_node("NameLabel")
		label.text = display_name
		
		# Setup OptionButton
		var opt = row.get_node("RoleOption")
		# Items are already set in scene, just need logic
		
		# Determine current selection
		var current_role = ControllerUtils.get_controller_role(device_id)
		
		if current_role == ControllerUtils.ROLE_AUTO:
			opt.selected = 0
		elif current_role == ControllerUtils.ROLE_P1:
			opt.selected = 1
		elif current_role == ControllerUtils.ROLE_P2:
			opt.selected = 2
		elif current_role == ControllerUtils.ROLE_DISABLED:
			opt.selected = 3
			
		opt.item_selected.connect(func(index):
			# Map Index -> Role
			var new_role = ControllerUtils.ROLE_AUTO
			if index == 0: new_role = ControllerUtils.ROLE_AUTO
			elif index == 1: new_role = ControllerUtils.ROLE_P1
			elif index == 2: new_role = ControllerUtils.ROLE_P2
			elif index == 3: new_role = ControllerUtils.ROLE_DISABLED
			
			ControllerUtils.controller_assignments[joy_name] = new_role
			
			# Trigger update in arranger immediately
			var arranger = get_tree().root.get_node_or_null("Main/Arranger")
			if arranger:
				arranger.update_controller_state()
		)
		
		# Setup Test Button
		var test_btn = row.get_node("TestBtn")
		test_btn.pressed.connect(func(): _show_test_popup(device_id))

		# Setup Export Button
		var export_btn = row.get_node("ExportBtn")
		export_btn.pressed.connect(func(): _export_mapping(device_id))

		container.add_child(row)
		
	if visible_count == 0:
		var label = Label.new()
		label.text = "No controllers connected."
		label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		container.add_child(label)

func _export_mapping(device_id: int):
	var guid = Input.get_joy_guid(device_id)
	var joy_name = Input.get_joy_name(device_id)
	var path = PicoBootManager.PUBLIC_FOLDER + "/sdl_controllers.txt"
	
	print("Attempting export for: ", joy_name, " [", guid, "]")
	
	if FileAccess.file_exists(path):
		var content = FileAccess.get_file_as_string(path)
		if guid in content:
			print("Mapping for GUID ", guid, " already exists in ", path)
			return

	var f = FileAccess.open(path, FileAccess.READ_WRITE)
	if not FileAccess.file_exists(path):
		f = FileAccess.open(path, FileAccess.WRITE)
	else:
		f.seek_end() # Append
		
	if f:
		f.store_line("# " + joy_name)
		# Template currently just adds the GUID and name, user must fill rest
		f.store_line("%s,%s,platform:Android," % [guid, joy_name])
		f.close()
		print("Exported mapping template to: ", path)
	else:
		print("Failed to open mapping file for writing: ", path)


func _show_test_popup(device_id: int):
	test_device_id = device_id
	test_popup.visible = true
	test_label.text = "Waiting..."
    # Helper label is static in scene now

func _input(event):
	if test_popup and is_instance_valid(test_popup) and test_popup.visible:
		if event.device == test_device_id:
			if event is InputEventJoypadButton and event.pressed:
				test_label.text = "Button %d -> b%d" % [event.button_index, event.button_index]
			elif event is InputEventJoypadMotion:
				if abs(event.axis_value) > 0.5:
					test_label.text = "Axis %d -> a%d" % [event.axis, event.axis]


func set_scale_factor(factor: float):
	scale = Vector2(factor, factor)
	call_deferred("_fit_to_screen")

func _fit_to_screen():
	# Clamp scale to fit screen
	var screen_size = get_viewport().get_visible_rect().size
	var current_size = size * scale
	
	# Margin 20px
	var max_w = screen_size.x - 40
	var max_h = screen_size.y - 40
	
	if current_size.x > max_w or current_size.y > max_h:
		var ratio_w = max_w / size.x
		var ratio_h = max_h / size.y
		var new_scale = min(scale.x, min(ratio_w, ratio_h))
		scale = Vector2(new_scale, new_scale)
		
	# Center it
	position = (screen_size - size * scale) / 2.0
