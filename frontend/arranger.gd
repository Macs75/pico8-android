extends Control

@export var active_area: Control
@export var reset_button: Button
@export var center_y: bool = false
@export var auto_show: bool = true
@export var kb_anchor: Node2D = null

var display_frame: Node2D = null
var landscape_ui: Control = null
var display_container: Node2D = null

var cached_kb_active: bool = false
var cached_controller_connected: bool = false

var dirty: bool = true
var last_screensize: Vector2i = Vector2i.ZERO
var dragging_pointer_index: int = -1

signal layout_updated()

var tex_x_normal = preload("res://assets/btn_x_normal.png")
var tex_x_pressed = preload("res://assets/btn_x_pressed.png")
var tex_o_normal = preload("res://assets/btn_o_normal.png")
var tex_o_pressed = preload("res://assets/btn_o_pressed.png")

var tex_mouse_l_normal = preload("res://assets/btn_mouse_left_normal.png")
var tex_mouse_l_pressed = preload("res://assets/btn_mouse_left_pressed.png")
var tex_mouse_r_normal = preload("res://assets/btn_mouse_right_normal.png")
var tex_mouse_r_pressed = preload("res://assets/btn_mouse_right_pressed.png")

func set_keyboard_active(active: bool):
	if cached_kb_active != active:
		cached_kb_active = active
		dirty = true

func update_controller_state():
	var new_state = ControllerUtils.is_real_controller_connected()
	if cached_controller_connected != new_state:
		cached_controller_connected = new_state
		dirty = true


func _ready() -> void:
	visible = false
	var streamer = get_parent()
	if streamer.has_signal("input_mode_changed"):
		streamer.input_mode_changed.connect(_update_buttons_for_mode)
		# Initialize buttons with current state
		_update_buttons_for_mode(streamer.get_input_mode() == streamer.InputMode.TRACKPAD)
	
	if has_node("displayContainer/DisplayFrame"):
		display_frame = get_node("displayContainer/DisplayFrame")
	
	if has_node("displayContainer"):
		display_container = get_node("displayContainer")
	
	# Attempt to find sibling LandscapeUI
	var parent = get_parent()
	if parent and parent.has_node("LandscapeUI"):
		landscape_ui = parent.get_node("LandscapeUI")
		
	if reset_button:
		reset_button.pressed.connect(_on_reset_display_pressed)
		_update_reset_button_visibility()
	
	if has_node("kbanchor"):
		kb_anchor = get_node("kbanchor")
	
	if has_node("Label"):
		get_node("Label").visible = false
	
	# Initial check
	update_controller_state()

	# Connect runcmd separately to avoid dependency issues if it's not ready yet
	# Trigger deferred setup to ensure runcmd is ready
	call_deferred("_setup_intent_listener")

	# Optimize: Listen for resize instead of polling
	get_tree().root.size_changed.connect(_on_resize)
	# Force initial layout check
	_on_resize()

func _setup_intent_listener():
	var runcmd = get_tree().root.get_node_or_null("Main/runcmd")
	if runcmd:
		if not runcmd.intent_session_started.is_connected(_on_intent_session_started):
			runcmd.intent_session_started.connect(_on_intent_session_started)
		# Check late join
		if runcmd.is_intent_session:
			_on_intent_session_started()

func _on_intent_session_started():
	# 1. Patch Gaming Keyboard (Node: 'esc')
	var gaming_esc = get_node_or_null("kbanchor/kb_gaming/esc")
	if gaming_esc:
		_patch_exit_button(gaming_esc)

func _patch_exit_button(btn: Control):
	# Load Power Icon (if not already loaded globally, load locally)
	var tex_pwr = load("res://assets/btn_power_normal.png")
	var tex_pwr_press = load("res://assets/btn_power_pressed.png")
	
	if btn.has_method("set_textures") and tex_pwr and tex_pwr_press:
		btn.set_textures(tex_pwr, tex_pwr_press)
		
	if "key_id" in btn:
		btn.key_id = "IntentExit"
	
	if btn.has_method("set_cap_text"):
		btn.cap_text = ""
	elif "text" in btn:
		btn.text = ""

var frames_rendered = 0

func _on_resize():
	# Update cached size and dirtiness
	var screensize = DisplayServer.window_get_size()
	if screensize != last_screensize:
		last_screensize = screensize
		_update_layout()


func _input(event: InputEvent) -> void:
	if not PicoVideoStreamer.display_drag_enabled:
		dragging_pointer_index = -1
		return
		
	if event is InputEventScreenTouch:
		if event.pressed:
			if dragging_pointer_index == -1:
				if display_container and display_container.visible:
					# Check if touch is inside the display sprite
					# Transform global event position to local space
					var local_pos = display_container.to_local(event.position)
					if display_container.get_rect().has_point(local_pos):
						dragging_pointer_index = event.index
		elif event.index == dragging_pointer_index:
			dragging_pointer_index = -1
			
	elif event is InputEventScreenDrag:
		if event.index == dragging_pointer_index:
			# Calculate orientation
			var is_landscape_now = PicoVideoStreamer.is_system_landscape()
			var current_offset = PicoVideoStreamer.get_display_drag_offset(is_landscape_now)
			PicoVideoStreamer.set_display_drag_offset(current_offset + event.relative, is_landscape_now)

func _on_reset_display_pressed():
	# Use new global reset that handles controls too
	PicoVideoStreamer.reset_display_layout(PicoVideoStreamer.is_system_landscape())

func _update_reset_button_visibility():
	if reset_button:
		reset_button.visible = PicoVideoStreamer.display_drag_enabled


func _process(_delta: float) -> void:
	if frames_rendered < 10:
		frames_rendered += 1
		# Force layout update during initial frames to settle
		_on_resize()
		_update_layout()
		return

	# Poll keyboard height only (Android specific weirdness often requires this)
	var real_kb_height = DisplayServer.virtual_keyboard_get_height()
	
	var kb_active_now = (real_kb_height > 0)
	if cached_kb_active != kb_active_now:
		cached_kb_active = kb_active_now
		if not cached_kb_active:
			# Restore focus to game loop if keyboard closed
			if PicoVideoStreamer.instance:
				PicoVideoStreamer.instance.release_input_locks()
		_update_layout()
		
	if dirty:
		_update_layout()

func _update_layout():
	dirty = false
	var screensize = last_screensize
	# If for some reason we missed a resize
	if screensize == Vector2i.ZERO:
		screensize = DisplayServer.window_get_size()
		last_screensize = screensize
		
	var kb_height = 0
	var is_landscape = PicoVideoStreamer.is_system_landscape()

	var target_size = Vector2(128, 128)
	var target_pos = Vector2.ZERO
	
	if active_area:
		target_size = active_area.size
		target_pos = active_area.position
	else:
		# Fallback if unassigned
		if has_node("ActiveArea"):
			active_area = get_node("ActiveArea")
			target_size = active_area.size
			target_pos = active_area.position
	
	# Reserve space for side controls:
	var available_size = Vector2(screensize)

	# Use cached state instead of polling every frame
	var is_controller_connected = cached_controller_connected
	
	# If Landscape OR Controller is connected, we target the game-only size (128x128)
	# BUT only if this is the actual game display (has display_container)
	var maxScale: float = 1.0
	var _scale_factor: float = 1.0
	
	if (is_landscape or is_controller_connected) and display_container:
		target_size = Vector2(128, 128)
		target_pos = Vector2(0, 0)
		
		var scale_calc_size = Vector2(128, 128)
		
		# Only reserve space for side controls if:
		# 1. We are physically in landscape (wide screen)
		# 2. AND No controller is connected (so we need on-screen controls)
		if is_landscape and not is_controller_connected:
			# We need approx 80 pixels of "game-scaled" space on each side.
			# 80 * 2 = 160. Total width 288.
			scale_calc_size.x += 160
		
		var ratio_x = available_size.x / scale_calc_size.x
		var ratio_y = available_size.y / scale_calc_size.y
		var raw_scale = min(ratio_x, ratio_y)
		
		if PicoVideoStreamer.get_integer_scaling_enabled():
			maxScale = max(1.0, floor(raw_scale))
		else:
			maxScale = max(1.0, raw_scale)
	else:
		# Standard scaling logic for portraits/menus
		var ratio_x = available_size.x / target_size.x
		var ratio_y = available_size.y / target_size.y
		var raw_scale = min(ratio_x, ratio_y)
		
		if PicoVideoStreamer.get_integer_scaling_enabled():
			maxScale = max(1.0, floor(raw_scale))
		else:
			maxScale = max(1.0, raw_scale)

	self.scale = Vector2(maxScale, maxScale)
	
	# Apply same scale to Reset Button (OverlayUI) as requested
	if reset_button:
		reset_button.scale = Vector2(maxScale, maxScale)
	
	# Compensate for Arranger zoom to keep high-res D-pad at constant physical size
	var dpad = get_node_or_null("kbanchor/kb_gaming/Onmipad")
	if dpad:
		var target_scale = 8.5 / float(maxScale)
		dpad.scale = Vector2(target_scale, target_scale)

	if auto_show and not visible:
		visible = true
	# Calculate kb_height based on overlap
	if cached_kb_active:
		var real_kb_h = DisplayServer.virtual_keyboard_get_height()
		var screen_bottom = 0
		
		if is_landscape:
			screen_bottom = (screensize.y / 2) + (64 * maxScale)
		else:
			var content_height = target_size.y * maxScale
			var arr_y = (screensize.y - content_height) / 2 if center_y else 0
			screen_bottom = arr_y + (140 * maxScale) # 140 = 12 (padding) + 128 (screen)
		
		if screen_bottom > (screensize.y - real_kb_h):
			kb_height = 64

	var extraSpace = Vector2(screensize) - (target_size * maxScale)
	if kb_height:
		extraSpace.y -= kb_height
		if KBMan.get_current_keyboard_type() == KBMan.KBType.FULL:
			extraSpace.y = max(-92 * maxScale, extraSpace.y)
		else:
			extraSpace.y = max(0, extraSpace.y)
			
	if display_frame:
		display_frame.visible = false
		
	# Keyboard Anchor Control
	if kb_anchor != null:
		var always_show = PicoVideoStreamer.get_always_show_controls()
		var is_full_kb = (KBMan.get_current_keyboard_type() == KBMan.KBType.FULL)
		
		if is_landscape:
			kb_anchor.visible = false # Always hide portrait anchor in landscape
		elif is_full_kb:
			kb_anchor.visible = true # Always show if Full Keyboard is requested (override controller hide)
		elif is_controller_connected and not always_show:
			kb_anchor.visible = false
		else:
			kb_anchor.visible = true


	if is_landscape:
		if landscape_ui:
			landscape_ui.visible = (not is_controller_connected) or PicoVideoStreamer.get_always_show_controls()
		# Perfect Centering for Landscape Game Display
		self.position = (Vector2(screensize) / 2).floor()
	else:
		if not center_y:
			extraSpace.y = 0
	# Portrait / Generic UI Centering Logic (Top-Left Logic)
		self.position = Vector2i(Vector2(extraSpace.x / 2, extraSpace.y / 2) - target_pos * maxScale)

	# 2. Configure Display Container (if exists)
	if display_container:
		display_container.centered = is_landscape
		
		# Ensure reset button visibility is correct
		_update_reset_button_visibility()
		
		# --- Display Drag Logic ---
		var drag_offset = PicoVideoStreamer.get_display_drag_offset(is_landscape)
		
		# 1. Calculate Baseline Position (where the display is with ZERO drag)
		var target_y_base = 0
		if not is_landscape:
			target_y_base = 12
		if kb_height > 0:
			target_y_base -= 64
			
		var baseline_global: Vector2
		if is_landscape:
			# Landscape is centered by default. 
			# display_container.centered = true, so its local origin (0,0) is center of display.
			# Its top-left is -(target_size/2).
			baseline_global = (Vector2(screensize) / 2.0) - (target_size * maxScale / 2.0).floor()
		else:
			# Portrait: Arranger.position + (0, target_y_base) * maxScale
			# display_container.centered = false, so its local origin (0,0) is its top-left.
			baseline_global = Vector2(self.position) + Vector2(0, target_y_base) * maxScale
		
		# 2. Clamping
		# Use 128x128 as the actual logical screen size for clamping, 
		# otherwise portrait's ActiveArea (300 height) restricts movement too much.
		var display_size_global = Vector2(128, 128) * maxScale
		
		# We want: 0 <= baseline_global + drag_offset <= screensize - display_size_global
		var min_offset = - baseline_global
		var max_offset = Vector2(screensize) - display_size_global - baseline_global
		
		# Add a tiny bit of padding if desired, but 0 is strict screen edges
		var clamped_global_x = clamp(drag_offset.x, min_offset.x, max_offset.x)
		var clamped_global_y = clamp(drag_offset.y, min_offset.y, max_offset.y)
		
		if not is_landscape and PicoVideoStreamer.display_drag_enabled:
			print("PORTRAIT DRAG DEBUG:")
			print("  ScreenSize: ", Vector2(screensize))
			print("  Baseline: ", baseline_global)
			print("  DisplaySize: ", display_size_global)
			print("  MinOffset: ", min_offset, " MaxOffset: ", max_offset)
			print("  CurrentDrag: ", drag_offset, " Clamped: ", Vector2(clamped_global_x, clamped_global_y))
		
		# Write back clamped value to global state so it doesn't drift
		if drag_offset.x != clamped_global_x or drag_offset.y != clamped_global_y:
			PicoVideoStreamer.set_display_drag_offset(Vector2(clamped_global_x, clamped_global_y), is_landscape)
			drag_offset = PicoVideoStreamer.get_display_drag_offset(is_landscape)
		
		# 3. Apply to Visuals
		var effective_drag = drag_offset / maxScale
		display_container.position = Vector2(effective_drag.x, target_y_base + effective_drag.y)
	
	layout_updated.emit()

func _update_buttons_for_mode(is_trackpad: bool):
	var x_btn = get_node_or_null("kbanchor/kb_gaming/X")
	var z_btn = get_node_or_null("kbanchor/kb_gaming/Z")
	
	if is_trackpad:
		if x_btn:
			x_btn.set_textures(tex_mouse_l_normal, tex_mouse_l_pressed)
				
		if z_btn:
			z_btn.set_textures(tex_mouse_r_normal, tex_mouse_r_pressed)
	else:
		if x_btn:
			x_btn.set_textures(tex_x_normal, tex_x_pressed)
		if z_btn:
			z_btn.set_textures(tex_o_normal, tex_o_pressed)
