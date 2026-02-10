extends CanvasLayer

var release_url: String = ""
var version_tag: String = ""

signal closed

func setup(tag: String, url: String):
	version_tag = tag
	release_url = url
	%VersionLabel.text = "v" + tag
	
	# Focus logic for controller support
	%CloseButton.grab_focus()

func _ready() -> void:
	%CloseButton.pressed.connect(_on_close_pressed)
	%LinkButton.pressed.connect(_on_link_pressed)
	
	# Initial Layout
	_update_layout()
	get_tree().root.size_changed.connect(_update_layout)
	
	# Connect Toggle
	%IgnoreButton.toggled.connect(_on_ignore_toggled)
	_on_ignore_toggled(false) # Set initial text
	
	# Animate in
	$Panel.pivot_offset = $Panel.size / 2
	$Panel.scale = Vector2(0.8, 0.8)
	var tween = create_tween()
	tween.tween_property($Panel, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_ignore_toggled(toggled: bool):
	if toggled:
		%IgnoreButton.text = "[X] IGNORE THIS UPDATE"
	else:
		%IgnoreButton.text = "[ ] IGNORE THIS UPDATE"

func _update_layout():
	var view_size = get_viewport().get_visible_rect().size
	var target_width = 300.0
	
	if view_size.x < view_size.y:
		# Portrait: Use 90% of width
		target_width = clamp(view_size.x * 0.9, 300, 600)
	else:
		# Landscape: Use 50% of width
		target_width = clamp(view_size.x * 0.5, 400, 600)
	
	$Panel.custom_minimum_size.x = target_width
	$Panel.size.x = target_width
	$Panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	
	# Update Pivot for animation
	$Panel.pivot_offset = $Panel.size / 2
	
	# Apply Font Styling
	var font_size = 12
	if view_size.y > 0:
		font_size = clamp(int(min(view_size.x, view_size.y) * 0.05), 12, 36)
	
	_apply_font_style(%Title, font_size * 1.2)
	_apply_font_style(%VersionLabel, font_size)
	_apply_font_style(%LinkButton, font_size)
	_apply_font_style(%IgnoreButton, font_size * 0.8)
	_apply_font_style(%CloseButton, font_size)
	
	# Apply Dynamic Margins (simulate 'em' units)
	var close_style = %CloseButton.get_theme_stylebox("normal")
	if close_style and close_style is StyleBoxFlat:
		# Duplicate to ensure we don't affect shared resources if any (though SubResource is usually safe)
		# But usually good practice if we modify it. 
		# However, SubResource is local.
		var h_margin = font_size * 0.8 # 0.8em
		var v_margin = font_size * 0.4 # 0.4em
		close_style.content_margin_left = h_margin
		close_style.content_margin_right = h_margin
		close_style.content_margin_top = v_margin
		close_style.content_margin_bottom = v_margin

func _apply_font_style(node: Control, size: int):
	node.add_theme_font_size_override("font_size", size)

func _on_link_pressed():
	if not release_url.is_empty():
		OS.shell_open(release_url)

func _on_close_pressed():
	var ignore_future = %IgnoreButton.button_pressed
	
	if ignore_future:
		# Save to config
		var config = ConfigFile.new()
		config.load("user://settings.cfg") # Load existing first to not wipe other settings
		config.set_value("updates", "ignored_tag", version_tag)
		config.save("user://settings.cfg")
	
	# Animate out
	var tween = create_tween()
	tween.tween_property($Panel, "scale", Vector2(0.8, 0.8), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property($Panel, "modulate:a", 0.0, 0.15)
	await tween.finished
	
	closed.emit()
	queue_free()

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JoyButton.JOY_BUTTON_DPAD_UP:
			_navigate_next(SIDE_TOP)
			get_viewport().set_input_as_handled()
		elif event.button_index == JoyButton.JOY_BUTTON_DPAD_DOWN:
			_navigate_next(SIDE_BOTTOM)
			get_viewport().set_input_as_handled()
		elif event.button_index == JoyButton.JOY_BUTTON_DPAD_LEFT:
			# Optional: Wrap or do nothing
			pass
		elif event.button_index == JoyButton.JOY_BUTTON_DPAD_RIGHT:
			pass
		elif event.button_index == JoyButton.JOY_BUTTON_A: # Confirm
			var focus_owner = get_viewport().gui_get_focus_owner()
			if focus_owner and focus_owner is Button:
				# Toggle if it's a toggle button, otherwise just press
				if focus_owner.toggle_mode:
					focus_owner.button_pressed = not focus_owner.button_pressed
				
				focus_owner.pressed.emit()
				get_viewport().set_input_as_handled()
		elif event.button_index == JoyButton.JOY_BUTTON_B: # Cancel/Back
			_on_close_pressed()
			get_viewport().set_input_as_handled()

func _navigate_next(side: Side):
	var current_focus = get_viewport().gui_get_focus_owner()
	if not current_focus:
		%CloseButton.grab_focus()
		return
		
	var neighbor = current_focus.find_valid_focus_neighbor(side)
	if neighbor:
		neighbor.grab_focus()
