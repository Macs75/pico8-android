extends Control

@onready var container = %VBoxContainer
@onready var close_btn = %ButtonClose

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
	_populate_list()

func _populate_list():
	# Clear existing children if any
	for child in container.get_children():
		child.queue_free()
		
	var joypads = ControllerUtils.get_real_controllers()
	
	if joypads.is_empty():
		var label = Label.new()
		label.text = "No controllers found."
		label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		container.add_child(label)
		return

	for device_id in joypads:
		var joy_name = Input.get_joy_name(device_id).to_lower()
		var display_name = joy_name
		if display_name.length() > 25:
			display_name = display_name.left(25) + "..."
			
		var check = CheckButton.new()
		check.text = display_name
		check.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		check.button_pressed = joy_name not in ControllerUtils.ignored_devices_by_user
		
		check.toggled.connect(func(toggled):
			if not toggled: # Unchecked = Ignore
				if joy_name not in ControllerUtils.ignored_devices_by_user:
					ControllerUtils.ignored_devices_by_user.append(joy_name)
			else: # Checked = Enable (Remove from ignore)
				ControllerUtils.ignored_devices_by_user.erase(joy_name)
			
			# Trigger update in arranger immediately
			var arranger = get_tree().root.get_node_or_null("Main/Arranger")
			if arranger:
				arranger.update_controller_state()
		)
		
		container.add_child(check)

func set_scale_factor(factor: float):
	scale = Vector2(factor, factor)
	# Center it? Handled by anchors usually if it's a full overlay, 
	# but if it's a popup we might need centering logic or PanelContainer
