extends Control

@export var active_area: Control
@export var reset_button: Button
@export var center_y: bool = false
@export var auto_show: bool = true
@export var kb_anchor: Node2D = null

var display_frame: Node2D = null
var landscape_ui: Control = null
var display_container: Node2D = null
@export var zoom_minus: Button
@export var zoom_plus: Button
@export var zoom_label: Label
@export var zoom_control: Control # This is the main LayoutControls VBox
@export var zoom_inner_container: Control # This is the ZoomControl HBox unit

var cached_kb_active: bool = false
var cached_controller_connected: bool = false

var dirty: bool = true
var last_screensize: Vector2i = Vector2i.ZERO
var dragging_pointer_index: int = -1
var active_touches = {}
var initial_pinch_dist = 0.0
var initial_scale_modifier = 1.0
var selection_outline: ReferenceRect = null

# Zoom Auto-Repeat Variables
var held_zoom_plus: bool = false
var held_zoom_minus: bool = false
var zoom_repeat_timer: float = 0.0
var zoom_repeat_delay: float = 0.0
const ZOOM_REPEAT_INITIAL_DELAY = 0.4
const ZOOM_REPEAT_MIN_DELAY = 0.02
const ZOOM_REPEAT_ACCEL = 0.8

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
	# Ensure Arranger covers screen for background gestures
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = MouseFilter.MOUSE_FILTER_PASS
	
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

	# Selection Outline Setup
	selection_outline = ReferenceRect.new()
	selection_outline.border_color = Color.RED
	selection_outline.border_width = 2.0
	selection_outline.editor_only = false
	selection_outline.mouse_filter = MouseFilter.MOUSE_FILTER_IGNORE
	selection_outline.visible = false
	selection_outline.top_level = true # Draw in global pixels
	add_child(selection_outline)
	
	if PicoVideoStreamer.instance:
		PicoVideoStreamer.instance.control_selected.connect(_on_control_selected)

	if zoom_minus:
		zoom_minus.button_down.connect(_on_zoom_minus_down)
		zoom_minus.button_up.connect(_on_zoom_minus_up)
		zoom_minus.mouse_exited.connect(_on_zoom_minus_up) # Safety release
	if zoom_plus:
		zoom_plus.button_down.connect(_on_zoom_plus_down)
		zoom_plus.button_up.connect(_on_zoom_plus_up)
		zoom_plus.mouse_exited.connect(_on_zoom_plus_up) # Safety release

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
	var gaming_esc = get_node_or_null("kbanchor/kb_gaming/Escape")
	if gaming_esc:
		_patch_exit_button(gaming_esc)

func _patch_exit_button(btn: Control):
	# Load Power Icon (if not already loaded globally, load locally)
	var tex_pwr = load("res://assets/btn_poweroff_normal.png")
	var tex_pwr_press = load("res://assets/btn_poweroff_pressed.png")
	
	if btn.has_method("set_textures") and tex_pwr and tex_pwr_press:
		btn.set_textures(tex_pwr, tex_pwr_press)
		
	if "key_id" in btn:
		btn.key_id = "IntentExit"

var frames_rendered = 0

func _on_resize():
	# Update cached size and dirtiness
	var screensize = DisplayServer.window_get_size()
	if screensize != last_screensize:
		last_screensize = screensize
		_update_layout()


func _input(event: InputEvent) -> void:
	if not visible or not PicoVideoStreamer.display_drag_enabled:
		active_touches.clear()
		dragging_pointer_index = -1
		_update_bezel_opacity()
		return
		
	var event_index = event.index if "index" in event else 0
	
	if event is InputEventScreenTouch:
		if event.pressed:
			active_touches[event_index] = event.position
			
			if active_touches.size() == 2:
				# Global Pinch Start: Target the SELECTED control
				var keys = active_touches.keys()
				initial_pinch_dist = active_touches[keys[0]].distance_to(active_touches[keys[1]])
				
				var sel = PicoVideoStreamer.instance.selected_control if PicoVideoStreamer.instance else null
				if sel == display_container:
					initial_scale_modifier = PicoVideoStreamer.get_display_scale_modifier(PicoVideoStreamer.is_system_landscape())
				elif sel:
					initial_scale_modifier = sel.scale.x
					if "original_scale" in sel:
						initial_scale_modifier = sel.scale.x / sel.original_scale.x
		else:
			active_touches.erase(event_index)
			if event_index == dragging_pointer_index:
				dragging_pointer_index = -1
			if active_touches.size() < 2:
				initial_pinch_dist = 0.0
				
	elif event is InputEventScreenDrag:
		if active_touches.has(event_index):
			active_touches[event_index] = event.position
		
		var sel = PicoVideoStreamer.instance.selected_control if PicoVideoStreamer.instance else null
		
		if active_touches.size() == 2:
			# Multi-touch: Global Pinch Zoom
			var keys = active_touches.keys()
			var current_dist = active_touches[keys[0]].distance_to(active_touches[keys[1]])
			if initial_pinch_dist > 0 and sel:
				var zoom_factor = current_dist / initial_pinch_dist
				var new_scale_mod = initial_scale_modifier * zoom_factor
				new_scale_mod = clamp(new_scale_mod, 0.25, 4.0)
				
				if sel == display_container:
					new_scale_mod = snapped(new_scale_mod, 0.01)
					PicoVideoStreamer.set_display_scale_modifier(new_scale_mod, PicoVideoStreamer.is_system_landscape())
				else:
					new_scale_mod = snapped(new_scale_mod, 0.01)
					if "original_scale" in sel:
						sel.scale = sel.original_scale * new_scale_mod
					else:
						sel.scale = Vector2.ONE * new_scale_mod
						
					if sel.has_method("_save_layout"):
						sel._save_layout()
				
				_update_zoom_label()
				
		elif active_touches.size() == 1 and event.index == dragging_pointer_index:
			# Background Drag: Only if we started on display
			var is_landscape_now = PicoVideoStreamer.is_system_landscape()
			var current_offset = PicoVideoStreamer.get_display_drag_offset(is_landscape_now)
			PicoVideoStreamer.set_display_drag_offset(current_offset + event.relative, is_landscape_now)

	_update_bezel_opacity()

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not PicoVideoStreamer.display_drag_enabled:
		return
		
	var event_index = event.index if "index" in event else 0
	
	if event is InputEventScreenTouch and event.pressed:
		# Selection for background/display if no button caught it
		var hit_display = false
		if display_container and display_container.visible:
			var local_pos = display_container.to_local(event.position)
			if display_container.get_rect().has_point(local_pos):
				hit_display = true

		if hit_display:
			if PicoVideoStreamer.instance:
				PicoVideoStreamer.instance.selected_control = display_container
				PicoVideoStreamer.instance.control_selected.emit(display_container)
			dragging_pointer_index = event_index
			# No need to accept_event in unhandled, but we track dragging_pointer_index locally

func _gui_input(_event: InputEvent) -> void:
	# Keep empty or remove - background touch is handled by _unhandled_input for robustness
	pass

func _on_reset_display_pressed():
	# Use new global reset that handles controls too
	PicoVideoStreamer.reset_display_layout(PicoVideoStreamer.is_system_landscape())

func _update_reset_button_visibility():
	if reset_button:
		reset_button.visible = PicoVideoStreamer.display_drag_enabled


func _process(_delta: float) -> void:
	# Keep zoom_control visibility synced with drag mode
	if zoom_control and zoom_control.visible != PicoVideoStreamer.display_drag_enabled:
		zoom_control.visible = PicoVideoStreamer.display_drag_enabled
		if zoom_control.visible:
			_update_zoom_label()
		else:
			# Deselect when customization is toggled off
			_clear_selection()
		
	# Handle Zoom Repeat
	if held_zoom_plus or held_zoom_minus:
		zoom_repeat_timer -= _delta
		if zoom_repeat_timer <= 0:
			if held_zoom_plus: _adjust_zoom(0.01)
			if held_zoom_minus: _adjust_zoom(-0.01)
			
			# Accelerate
			zoom_repeat_delay = max(ZOOM_REPEAT_MIN_DELAY, zoom_repeat_delay * ZOOM_REPEAT_ACCEL)
			zoom_repeat_timer = zoom_repeat_delay
		
	if selection_outline and selection_outline.visible:
		_update_selection_outline()
		
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
	var baselineScale: float = 1.0
	var zoomScale: float = 1.0
	
	if (is_landscape or is_controller_connected) and display_container:
		target_size = Vector2(128, 128)
		target_pos = Vector2(0, 0)
		var scale_calc_size = Vector2(128, 128)
		
		if is_landscape and not is_controller_connected:
			scale_calc_size.x += 160
		
		var ratio_x = available_size.x / scale_calc_size.x
		var ratio_y = available_size.y / scale_calc_size.y
		var raw_scale = min(ratio_x, ratio_y)
		
		# Baseline Fit
		if PicoVideoStreamer.get_integer_scaling_enabled():
			baselineScale = max(1.0, floor(raw_scale))
		else:
			baselineScale = max(1.0, raw_scale)
			
		# Effective Zoom
		var modifier = PicoVideoStreamer.get_display_scale_modifier(is_landscape)
		var raw_zoom = raw_scale * modifier
		if PicoVideoStreamer.get_integer_scaling_enabled():
			zoomScale = max(1.0, floor(raw_zoom))
		else:
			zoomScale = max(1.0, raw_zoom)
	else:
		var ratio_x = available_size.x / target_size.x
		var ratio_y = available_size.y / target_size.y
		var raw_scale = min(ratio_x, ratio_y)
		
		if PicoVideoStreamer.get_integer_scaling_enabled():
			baselineScale = max(1.0, floor(raw_scale))
		else:
			baselineScale = max(1.0, raw_scale)
			
		var modifier = PicoVideoStreamer.get_display_scale_modifier(is_landscape)
		var raw_zoom = raw_scale * modifier
		if PicoVideoStreamer.get_integer_scaling_enabled():
			zoomScale = max(1.0, floor(raw_zoom))
		else:
			zoomScale = max(1.0, raw_zoom)

	# 1. UI Baseline Scale (Buttons, etc.)
	self.scale = Vector2(baselineScale, baselineScale)
	
	# Shorthand for existing logic that uses 'maxScale'
	var maxScale = baselineScale
	
	# Apply same scale to Layout Controls (OverlayUI) 
	# Reset button is a child of zoom_control, so we only scale the parent.
	if zoom_control:
		zoom_control.scale = Vector2(maxScale, maxScale)
		# Ensure pivot is at the bottom-left of the container 
		# for consistent growth regardless of content size.
		zoom_control.pivot_offset = Vector2(0, zoom_control.size.y)
	
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
		var mode = PicoVideoStreamer.get_controls_mode()
		var is_full_kb = (KBMan.get_current_keyboard_type() == KBMan.KBType.FULL)
		
		# Hierarchy of overrides:
		# 1. Full Keyboard requested -> ALWAYS SHOW (unless landscape logic overrides, handled below)
		# 2. Controls Disabled -> ALWAYS HIDE
		# 3. Controls Forced -> ALWAYS SHOW
		# 4. Auto -> Hide if controller connected
		
		if is_landscape:
			kb_anchor.visible = false # Always hide portrait anchor in landscape
		elif is_full_kb:
			kb_anchor.visible = true
		elif mode == PicoVideoStreamer.ControlsMode.DISABLED:
			kb_anchor.visible = false
		elif mode == PicoVideoStreamer.ControlsMode.FORCE:
			kb_anchor.visible = true
		elif is_controller_connected: # Auto mode implied
			kb_anchor.visible = false
		else:
			kb_anchor.visible = true


	if is_landscape:
		if landscape_ui:
			var mode = PicoVideoStreamer.get_controls_mode()
			if mode == PicoVideoStreamer.ControlsMode.DISABLED:
				landscape_ui.visible = false
			elif mode == PicoVideoStreamer.ControlsMode.FORCE:
				landscape_ui.visible = true
			else: # Auto
				landscape_ui.visible = not is_controller_connected
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
		# Apply zooming ONLY to the display container
		var display_zoom_relative = zoomScale / baselineScale
		display_container.scale = Vector2(display_zoom_relative, display_zoom_relative)
		
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
			baseline_global = (Vector2(screensize) / 2.0) - (target_size * zoomScale / 2.0).floor()
		else:
			# Portrait: Arranger.position + (0, target_y_base) * baselineScale
			baseline_global = Vector2(self.position) + Vector2(0, target_y_base) * baselineScale
		
		# 2. Clamping
		# Use zoomScale for the actual visible size of the display
		var display_size_global = Vector2(128, 128) * zoomScale
		
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
	var z_btn = get_node_or_null("kbanchor/kb_gaming/O")
	
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

func _on_control_selected(_control: CanvasItem):
	selection_outline.visible = true
	_update_selection_outline()
	_update_zoom_label()


func _update_selection_outline():
	var streamer = PicoVideoStreamer.instance
	var sel = streamer.selected_control if streamer else null
	if not sel or not is_instance_valid(sel):
		selection_outline.visible = false
		return
		
	var global_rect: Rect2
	if sel is Control:
		global_rect = sel.get_global_rect()
	elif sel is Node2D:
		var l_rect = sel.get_rect()
		# For centered nodes, get_rect().position is typically -size/2
		# to_global handles the center offset correctly
		var global_pos = sel.to_global(l_rect.position)
		global_rect = Rect2(global_pos, l_rect.size * sel.get_global_transform().get_scale())
		
	# Since selection_outline is top_level, we use global pixels directly
	selection_outline.position = global_rect.position
	selection_outline.size = global_rect.size

func _on_zoom_minus_down():
	held_zoom_minus = true
	zoom_repeat_delay = ZOOM_REPEAT_INITIAL_DELAY
	zoom_repeat_timer = ZOOM_REPEAT_INITIAL_DELAY
	_adjust_zoom(-0.01)

func _on_zoom_minus_up():
	held_zoom_minus = false

func _on_zoom_plus_down():
	held_zoom_plus = true
	zoom_repeat_delay = ZOOM_REPEAT_INITIAL_DELAY
	zoom_repeat_timer = ZOOM_REPEAT_INITIAL_DELAY
	_adjust_zoom(0.01)

func _on_zoom_plus_up():
	held_zoom_plus = false

func _adjust_zoom(delta: float):
	var streamer = PicoVideoStreamer.instance
	var sel = streamer.selected_control if streamer else null
	if not sel or not is_instance_valid(sel): return
	
	var is_landscape = PicoVideoStreamer.is_system_landscape()
	if sel == display_container:
		var cur = PicoVideoStreamer.get_display_scale_modifier(is_landscape)
		PicoVideoStreamer.set_display_scale_modifier(clamp(cur + delta, 0.25, 4.0), is_landscape)
	else:
		var cur_mod = 1.0
		if "original_scale" in sel:
			cur_mod = sel.scale.x / sel.original_scale.x
		else:
			cur_mod = sel.scale.x
			
		var new_mod = clamp(cur_mod + delta, 0.25, 4.0)
		new_mod = snapped(new_mod, 0.01)
		
		if "original_scale" in sel:
			sel.scale = sel.original_scale * new_mod
		else:
			sel.scale = Vector2.ONE * new_mod
			
		if sel.has_method("_save_layout"):
			sel._save_layout()
	
	_update_selection_outline()
	_update_zoom_label()

func _clear_selection():
	if PicoVideoStreamer.instance:
		PicoVideoStreamer.instance.selected_control = null
		PicoVideoStreamer.instance.control_selected.emit(null)
	
	if selection_outline:
		selection_outline.visible = false
	
	_update_zoom_label()

func _update_zoom_label():
	var streamer = PicoVideoStreamer.instance
	var sel = streamer.selected_control if streamer else null
	
	# Reset button is part of zoom_control which is managed in _process
	# Inner zoom unit (+/-/label) only shows when something is selected
	if zoom_inner_container:
		zoom_inner_container.visible = (sel != null and is_instance_valid(sel))
	
	if not sel or not is_instance_valid(sel) or not zoom_label:
		return
	
	var cur_scale = 1.0
	if sel == display_container:
		cur_scale = PicoVideoStreamer.get_display_scale_modifier(PicoVideoStreamer.is_system_landscape())
	else:
		if "original_scale" in sel:
			cur_scale = sel.scale.x / sel.original_scale.x
		else:
			cur_scale = sel.scale.x
			
	zoom_label.text = "%.2fx" % cur_scale

func _update_bezel_opacity():
	if PicoVideoStreamer.instance and PicoVideoStreamer.instance.bezel_overlay:
		var dragging = active_touches.size() > 0 and PicoVideoStreamer.display_drag_enabled
		var target_alpha = 0.4 if dragging else 1.0
		if PicoVideoStreamer.instance.bezel_overlay.modulate.a != target_alpha:
			PicoVideoStreamer.instance.bezel_overlay.modulate.a = target_alpha
