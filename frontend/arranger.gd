extends Node2D

@export var rect: Control
@export var center_y: bool = false
@export var kb_anchor: Node2D = null

var display_frame: Node2D = null
var landscape_ui: CanvasLayer = null
var hbox_container: Control = null
var display_container: Node2D = null

var cached_kb_active: bool = false
var cached_controller_connected: bool = false

var dirty: bool = true
var last_screensize: Vector2i = Vector2i.ZERO

func set_keyboard_active(active: bool):
	if cached_kb_active != active:
		cached_kb_active = active
		dirty = true

func update_controller_state():
	var new_state = _is_real_controller_connected()
	if cached_controller_connected != new_state:
		cached_controller_connected = new_state
		dirty = true

func _ready() -> void:
	if has_node("displayContainer/DisplayFrame"):
		display_frame = get_node("displayContainer/DisplayFrame")
	
	if has_node("displayContainer"):
		display_container = get_node("displayContainer")
	
	if has_node("HBoxContainer"):
		hbox_container = get_node("HBoxContainer")
	
	# Attempt to find sibling LandscapeUI
	var parent = get_parent()
	if parent and parent.has_node("LandscapeUI"):
		landscape_ui = parent.get_node("LandscapeUI")
	
	if has_node("kbanchor"):
		kb_anchor = get_node("kbanchor")
	
	if has_node("Label"):
		get_node("Label").visible = false
	
	# Initial check
	update_controller_state()
	visible = false

var frames_rendered = 0

func _process(delta: float) -> void:
	if frames_rendered < 10:
		frames_rendered += 1
		return
		
	var screensize := DisplayServer.window_get_size()
	if screensize.x == 0 or screensize.y == 0:
		return
		
	if screensize != last_screensize:
		dirty = true
		last_screensize = screensize
		# Safe to check keyboard height on resize (rare event)
		var real_kb_height = DisplayServer.virtual_keyboard_get_height()
		if real_kb_height == 0:
			cached_kb_active = false
			# Restore focus to game loop if keyboard closed
			if PicoVideoStreamer.instance:
				PicoVideoStreamer.instance.release_input_locks()
		
		if real_kb_height > 0:
			cached_kb_active = true
		
	if not dirty:
		return
	dirty = false # Reset flag
	
	var kb_height = 0
	if cached_kb_active:
		kb_height = 64 # Hardcoded generic height for offset logic if active
	
	var is_landscape = screensize.x >= screensize.y

	
	var target_size = rect.size
	var target_pos = rect.position
	
	# Reserve space for side controls:
	# Assume we need at least some pixels on each side.
	# Let's subtract a "safe zone" width from the available screen width calculation.
	var available_size = Vector2(screensize)


	
	# Use cached state instead of polling every frame
	var is_controller_connected = cached_controller_connected
	
	# If Landscape OR Controller is connected, we target the game-only size (128x128)
	if is_landscape or is_controller_connected:
		target_size = Vector2(128, 128)
		target_pos = Vector2(0, 0)
		
		# Only reserve space for side controls if:
		# 1. We are physically in landscape (wide screen)
		# 2. AND No controller is connected (so we need on-screen controls)
		if is_landscape and not is_controller_connected:
			available_size.x -= 250
		
	var maxScale: int = max(1, floor(min(
		available_size.x/target_size.x, available_size.y/target_size.y
	)))
	self.scale = Vector2(maxScale, maxScale)
	
	if not visible:
		visible = true	# Use ACTUAL screensize for centering logic, but calculated scale based on reduced size
	var extraSpace = Vector2(screensize) - (target_size*maxScale)
	if kb_height:
		extraSpace.y -= kb_height
		if KBMan.get_current_keyboard_type() == KBMan.KBType.FULL:
			extraSpace.y = max(-92*maxScale, extraSpace.y)
		else:
			extraSpace.y = max(0, extraSpace.y)
	if kb_anchor != null:
		if is_landscape or is_controller_connected:
			kb_anchor.visible = false
		else:
			kb_anchor.visible = true
			kb_anchor.position.y = (rect.size.y + extraSpace.y/maxScale - 18)
			
	if hbox_container:
		hbox_container.visible = not is_controller_connected

	# Force control of LandscapeUI visibility from here
	if landscape_ui:
		if is_controller_connected:
			landscape_ui.visible = false
		else:
			landscape_ui.visible = is_landscape
			
	if display_frame:
		display_frame.visible = false
		
	# Keyboard Anchor Control
	if kb_anchor != null:
		if is_landscape or is_controller_connected:
			# Normal logic: Hide in landscape or if controller connected
			kb_anchor.visible = false
		else:
			# Normal Portrait logic
			kb_anchor.visible = true
			kb_anchor.position.y = (rect.size.y + extraSpace.y/maxScale - 18)

	if not center_y and not is_landscape:
		extraSpace.y = 0
	
	if is_landscape:
		# Perfect Centering for Landscape
		self.position = (Vector2(screensize) / 2).floor()
		if display_container:
			display_container.centered = true
			var target_land_y = 0
			if kb_height > 0:
				target_land_y = -64
			display_container.position = Vector2(0, target_land_y)
	else:
		# Portrait / Default Top-Left Logic
		self.position = Vector2i(Vector2(extraSpace.x/2, extraSpace.y/2) - target_pos*maxScale)
		if display_container:
			display_container.centered = false
			
			var target_y = 0
			# Base offset
			if not is_landscape:
				target_y = 12
				
			# Keyboard offset (move up to show bottom text)
			if kb_height > 0:
				target_y -= 64
				
			display_container.position.y = target_y

func _is_real_controller_connected() -> bool:
	var joypads = Input.get_connected_joypads()
	for device_id in joypads:
		var name = Input.get_joy_name(device_id).to_lower()
		
		# Filter out common non-gamepad devices on Android
		if ("accelerometer" in name or "gyro" in name or "sensor" in name or 
			"virtual" in name or "touch" in name or "keypad" in name or "stylus" in name or
			"uinput-fpc" in name):
			continue
			
		return true
	
	return false
