class_name UIUtils
extends Object

static func create_pixel_button(text: String, size: int = 32) -> Button:
	var btn = Button.new()
	btn.text = text
	
	btn.add_theme_font_size_override("font_size", size)
	
	# Minimal style for pixel art look
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color(0.2, 0.2, 0.3, 1)
	
	# Dynamic Padding: Slim vertical, Wide horizontal
	var pad_v = int(size * 0.4) # Increased slightly for PressStart2P validity
	var pad_h = int(size * 0.8)
	
	style_normal.content_margin_top = pad_v
	style_normal.content_margin_bottom = pad_v
	style_normal.content_margin_left = pad_h
	style_normal.content_margin_right = pad_h
	
	var style_pressed = StyleBoxFlat.new()
	style_pressed.bg_color = Color(1, 0.2, 0.4, 1) # Pico-8 Redish
	style_pressed.content_margin_top = pad_v
	style_pressed.content_margin_bottom = pad_v
	style_pressed.content_margin_left = pad_h
	style_pressed.content_margin_right = pad_h
	
	# Focus Style (Lighter background + White Border)
	var style_focus = StyleBoxFlat.new()
	style_focus.bg_color = Color(0.4, 0.4, 0.5, 1) # Lighter
	style_focus.border_width_bottom = 2
	style_focus.border_width_top = 2
	style_focus.border_width_left = 2
	style_focus.border_width_right = 2
	style_focus.border_color = Color(1, 1, 1, 1)
	style_focus.content_margin_top = pad_v
	style_focus.content_margin_bottom = pad_v
	style_focus.content_margin_left = pad_h
	style_focus.content_margin_right = pad_h
	
	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_focus) # Hover same as focus
	btn.add_theme_stylebox_override("pressed", style_pressed)
	btn.add_theme_stylebox_override("focus", style_focus)
	
	return btn

static func create_confirm_dialog(parent: Node, _title: String, text: String, confirm_label: String, cancel_label: String, confirm_focus: bool, confirm_callback: Callable, cancel_callback: Callable) -> Control:
	var overlay = Control.new()
	overlay.name = "CustomConfirmDialog"
	overlay.set_script(load("res://dialog_handler.gd"))
	overlay.cancel_callback = cancel_callback
	overlay.top_level = true
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	# Ensure it's on top
	if parent is CanvasLayer:
		parent.add_child(overlay)
	else:
		# If adding to a normal node, might need high z-index or be last child
		parent.add_child(overlay)
		overlay.z_index = 4096 # High value to likely stay on top
	
	# Dimmer
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.8)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP # Block input
	overlay.add_child(bg)
	
	# Robust Centering Container
	var center_container = CenterContainer.new()
	center_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center_container)
	
	# Panel
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 1.0)
	style.border_width_left = 4
	style.border_width_top = 4
	style.border_width_right = 4
	style.border_width_bottom = 4
	style.border_color = Color(1, 1, 1, 1)
	style.expand_margin_top = 10
	style.expand_margin_bottom = 10
	style.expand_margin_left = 10
	style.expand_margin_right = 10
	panel.add_theme_stylebox_override("panel", style)
	center_container.add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 40)
	# Add padding around the VBox content
	var margin_container = MarginContainer.new()
	margin_container.add_theme_constant_override("margin_top", 40)
	margin_container.add_theme_constant_override("margin_bottom", 40)
	margin_container.add_theme_constant_override("margin_left", 40)
	margin_container.add_theme_constant_override("margin_right", 40)
	margin_container.add_child(vbox)
	panel.add_child(margin_container)
	
	# Calculate dynamic font size (5% of screen height, clamped)
	# We rely on the parent's viewport
	var viewport = parent.get_viewport()
	var screen_size = viewport.get_visible_rect().size if viewport else Vector2(1024, 600)
	var dynamic_font_size = 12 # Default fallback
	if screen_size.y > 0:
		dynamic_font_size = clamp(int(min(screen_size.x, screen_size.y) * 0.03), 12, 64)
	
	# Title / Text
	# If we have both, maybe title is bigger? For now, just using text as the main message.
	# The user's example in video_streamer just had one label "RETURN TO LAUNCHER?".
	var label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD # Enable wrap for small screens
	label.add_theme_font_size_override("font_size", dynamic_font_size)
	vbox.add_child(label)
	
	# Constraint width to 80% of screen
	if screen_size.x > 0:
		panel.custom_minimum_size.x = min(800, screen_size.x * 0.8)
	
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", int(dynamic_font_size * 1.25))
	vbox.add_child(hbox)
	
	# Cancel Button
	var btn_cancel = create_pixel_button(cancel_label, dynamic_font_size)
	btn_cancel.pressed.connect(cancel_callback)
	hbox.add_child(btn_cancel)
	
	# Confirm Button
	var btn_confirm = create_pixel_button(confirm_label, dynamic_font_size)
	btn_confirm.pressed.connect(confirm_callback)
	hbox.add_child(btn_confirm)
	
	var focus_target = btn_cancel if not confirm_focus else btn_confirm
	focus_target.grab_focus.call_deferred()

	# We also connect to visibility_changed to re-grab if shown later.	
	overlay.visibility_changed.connect(func():
		if overlay.visible:
			focus_target.grab_focus.call_deferred()
	)
	
	return overlay

static func create_message_dialog(parent: Node, _title: String, text: String, button_label: String = "OK", callback: Callable = Callable()) -> Control:
	var overlay = Control.new()
	overlay.name = "CustomMessageDialog"
	overlay.set_script(load("res://dialog_handler.gd"))
	# For message dialog, the "Cancel" action (B) usually just closes it, same as the button
	if callback.is_valid():
		overlay.cancel_callback = callback
	else:
		overlay.cancel_callback = overlay.queue_free
	overlay.top_level = true
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	if parent is CanvasLayer:
		parent.add_child(overlay)
	else:
		parent.add_child(overlay)
		overlay.z_index = 4096 # High Z-Index to cover everything, including bezel (100) and other dialogs
	
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.8)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(bg)
	
	var center_container = CenterContainer.new()
	center_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center_container)
	
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 1.0)
	style.border_width_left = 4
	style.border_width_top = 4
	style.border_width_right = 4
	style.border_width_bottom = 4
	style.border_color = Color(1, 1, 1, 1)
	style.expand_margin_top = 10
	style.expand_margin_bottom = 10
	style.expand_margin_left = 10
	style.expand_margin_right = 10
	panel.add_theme_stylebox_override("panel", style)
	center_container.add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 40)
	var margin_container = MarginContainer.new()
	margin_container.add_theme_constant_override("margin_top", 40)
	margin_container.add_theme_constant_override("margin_bottom", 40)
	margin_container.add_theme_constant_override("margin_left", 40)
	margin_container.add_theme_constant_override("margin_right", 40)
	margin_container.add_child(vbox)
	panel.add_child(margin_container)
	
	var viewport = parent.get_viewport()
	var screen_size = viewport.get_visible_rect().size if viewport else Vector2(1024, 600)
	var dynamic_font_size = 28
	if screen_size.y > 0:
		dynamic_font_size = clamp(int(min(screen_size.x, screen_size.y) * 0.03), 16, 64)
		
	var label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.add_theme_font_size_override("font_size", dynamic_font_size)
	vbox.add_child(label)
	
	if screen_size.x > 0:
		panel.custom_minimum_size.x = min(800, screen_size.x * 0.8)
		
	if not button_label.is_empty():
		var hbox = HBoxContainer.new()
		hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.add_child(hbox)
		
		var btn = create_pixel_button(button_label, dynamic_font_size)
		if callback.is_valid():
			btn.pressed.connect(callback)
		# Always connect to queue_free internal logic?
		# or let callback handle it. 
		# If callback is provided, we assume it handles logic.
		# But usually we want to close.
		# Let's clean up automatically if callback doesn't
		btn.pressed.connect(overlay.queue_free)
		
		hbox.add_child(btn)
		
		# Robust Focus Logic
		# We defer this to ensure the node is ready and top_level updates are processed.
		# We also connect to visibility_changed to re-grab if shown later.
		var focus_target = btn
		focus_target.grab_focus.call_deferred()
		
		overlay.visibility_changed.connect(func():
			if overlay.visible:
				focus_target.grab_focus.call_deferred()
		)
	
	return overlay
