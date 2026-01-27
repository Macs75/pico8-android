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
			
		var row = HBoxContainer.new()
		
		var label = Label.new()
		label.text = display_name
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		
		var opt = OptionButton.new()
		opt.add_item("Auto (Default)", ControllerUtils.ROLE_AUTO) # ID -1
		opt.add_item("Player 1", ControllerUtils.ROLE_P1) # ID 0
		opt.add_item("Player 2", ControllerUtils.ROLE_P2) # ID 1
		opt.add_item("Disabled", ControllerUtils.ROLE_DISABLED) # ID 2
		
		# Determine current selection
		var current_role = ControllerUtils.get_controller_role(device_id)
		
		# Map Role ID to Option Index? No, OptionButton stores IDs if we use add_item(label, id).
		# But `selected` property works on INDEX (0, 1, 2, 3...)
		# We must map Role -> Index
		# Index 0: Auto (ROLE_AUTO = -1)
		# Index 1: P1 (ROLE_P1 = 0)
		# Index 2: P2 (ROLE_P2 = 1)
		# Index 3: Disabled (ROLE_DISABLED = 2)
		
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
		
		row.add_child(opt)
		container.add_child(row)
		
	if visible_count == 0:
		var label = Label.new()
		label.text = "No controllers connected."
		label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		container.add_child(label)

func set_scale_factor(factor: float):
	scale = Vector2(factor, factor)
	# Center it? Handled by anchors usually if it's a full overlay, 
	# but if it's a popup we might need centering logic or PanelContainer
