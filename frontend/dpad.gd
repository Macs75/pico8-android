extends TextureRect

func send_ev(key: String, down: bool):
	PicoVideoStreamer.instance.vkb_setstate(key, down)

var center_offset = Vector2.ZERO
const SHIFT = Vector2(13.5, 13.5)
const ORIGIN = Vector2(0, 0)

@onready var lit_texture = preload("res://assets/dpad_lit.png")
@onready var default_texture = preload("res://assets/dpad.png")

var original_position: Vector2
var original_scale: Vector2
var editor_scale: Vector2
var drag_offset_start: Vector2

var active_touches = {}
var initial_pinch_dist = 0.0
var initial_scale_modifier = 1.0

const CustomControlTextures = preload("res://custom_control_textures.gd")

# Track if press effect is enabled (for custom textures without pressed variant)
var has_press_effect: bool = true


func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_filter = Control.MOUSE_FILTER_STOP
	center_offset = size / 2
	
	# Reset all
	update_visuals(Vector2i.ONE)
	
	# --- Drag & Drop Init ---
	original_position = position
	original_scale = scale
	editor_scale = scale
	PicoVideoStreamer.instance.layout_reset.connect(_on_layout_reset)
	
	# Attempt to load saved position and scale
	var is_landscape = _is_in_landscape_ui()
	var saved_pos = PicoVideoStreamer.get_control_pos(name, is_landscape)
	if saved_pos != null:
		position = saved_pos
	
	var saved_scale = PicoVideoStreamer.get_control_scale(name, is_landscape)
	scale = original_scale * saved_scale
	
	# --- Custom Texture Loading ---
	# Load default sprites logic initially
	if not _load_and_apply_custom_textures(is_landscape):
		# Setup default sprites if no custom texture
		_setup_dpad_sprites(lit_texture)

func reload_textures():
	var is_landscape = _is_in_landscape_ui()
	
	# Reset defaults first
	lit_texture = preload("res://assets/dpad_lit.png")
	self.texture = default_texture
	has_press_effect = true
	
	# Try Load Custom
	if not _load_and_apply_custom_textures(is_landscape):
		var saved_scale = PicoVideoStreamer.get_control_scale(name, is_landscape)
		scale = original_scale * saved_scale
		
		_setup_dpad_sprites(lit_texture)
		z_index = 0 # Default z-index? Or whatever it was.

func _load_and_apply_custom_textures(is_landscape: bool) -> bool:
	var custom_textures = CustomControlTextures.get_custom_textures("dpad", is_landscape)
	if custom_textures[0] != null:
		self.texture = custom_textures[0]
		self.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		
		if custom_textures[1] != null:
			lit_texture = custom_textures[1]
			has_press_effect = true
		else:
			has_press_effect = false
			
		# Apply sprites (if press effect enabled, or just to be safe if enabled later)
		_setup_dpad_sprites(lit_texture)
			
		# Aspect Ratio Logic
		var tex_size = custom_textures[0].get_size()
		if tex_size.x > 0 and tex_size.y > 0:
			var tex_aspect = tex_size.x / tex_size.y
			var dpad_size = self.size if self.size.y > 0 else (texture.get_size() if texture else Vector2(100, 100))
			var dpad_aspect = dpad_size.x / dpad_size.y if dpad_size.y > 0 else 1.0
			
			if abs(tex_aspect - dpad_aspect) > 0.01:
				var area = dpad_size.x * dpad_size.y
				var new_width = sqrt(area * tex_aspect)
				var new_height = new_width / tex_aspect
				
				# Use editor_scale as base
				scale.x = (new_width / dpad_size.x) * editor_scale.x
				scale.y = (new_height / dpad_size.y) * editor_scale.y
				
		z_index = 150
		return true
	
	return false

func _setup_dpad_sprites(tex: Texture2D):
	var w = tex.get_width()
	var h = tex.get_height()
	var s_w = w / 3.0
	var s_h = h / 3.0
	
	# Destination sizing
	var dest_w = size.x / 3.0
	var dest_h = size.y / 3.0
	
	# Helper to setup a slice
	_setup_slice(%Up, tex, Rect2(s_w, 0, s_w, s_h), Vector2(dest_w, 0), Vector2(dest_w, dest_h))
	_setup_slice(%Down, tex, Rect2(s_w, s_h * 2, s_w, s_h), Vector2(dest_w, dest_h * 2), Vector2(dest_w, dest_h))
	_setup_slice(%Left, tex, Rect2(0, s_h, s_w, s_h), Vector2(0, dest_h), Vector2(dest_w, dest_h))
	_setup_slice(%Right, tex, Rect2(s_w * 2, s_h, s_w, s_h), Vector2(dest_w * 2, dest_h), Vector2(dest_w, dest_h))

func _setup_slice(node: TextureRect, atlas: Texture2D, region: Rect2, pos: Vector2, slice_size: Vector2):
	if not node: return
	
	var at = node.texture as AtlasTexture
	if not at:
		at = AtlasTexture.new()
		node.texture = at
	
	at.atlas = atlas
	at.region = region
	at.filter_clip = true
	
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.position = pos
	node.size = slice_size
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _is_in_landscape_ui() -> bool:
	var p = get_parent()
	while p:
		if p.name == "LandscapeUI":
			return true
		p = p.get_parent()
	return false

func _save_layout():
	var current_scale_mod = scale.x / original_scale.x
	PicoVideoStreamer.set_control_layout_data(name, position, current_scale_mod, _is_in_landscape_ui())

func _on_layout_reset(target_is_landscape: bool):
	if target_is_landscape == _is_in_landscape_ui():
		position = original_position
		scale = original_scale


func constrain(val: float, shift: float, _origin: float):
	# Symmetric deadzone logic
	var threshold = shift * 0.4
	
	if val < -threshold:
		return 0
	elif val > threshold:
		return 2
	else:
		return 1

var current_dir = Vector2i.ONE

func dir2keys(dir: Vector2i):
	var keys = []
	if dir.x == 0: keys.append("Left")
	if dir.x == 2: keys.append("Right")
	if dir.y == 0: keys.append("Up")
	if dir.y == 2: keys.append("Down")
	return keys

func update_dir(new_dir: Vector2i):
	if new_dir == current_dir:
		return
	var old_keys = dir2keys(current_dir)
	var new_keys = dir2keys(new_dir)
	for k in old_keys:
		if k not in new_keys:
			send_ev(k, false)
	for k in new_keys:
		if k not in old_keys:
			send_ev(k, true)
	current_dir = new_dir
	update_visuals(new_dir)

func update_visuals(dir: Vector2i):
	# Only update visuals if press effect is enabled
	if has_press_effect:
		# Center is (1,1)
		%Left.visible = (dir.x == 0)
		%Right.visible = (dir.x == 2)
		%Up.visible = (dir.y == 0)
		%Down.visible = (dir.y == 2)

func _gui_input(event: InputEvent) -> void:
	if PicoVideoStreamer.display_drag_enabled:
		var event_index = event.index if "index" in event else 0
		if event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
			if event.pressed:
				drag_offset_start = event.position
				active_touches[event_index] = event.position
				
				# Centralized Selection: Update the last touched element
				if PicoVideoStreamer.instance:
					PicoVideoStreamer.instance.selected_control = self
					PicoVideoStreamer.instance.control_selected.emit(self)
				
				accept_event()
			else:
				active_touches.erase(event_index)
				_save_layout()
				accept_event()
		elif event is InputEventScreenDrag or (event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT)):
			if active_touches.has(event_index):
				active_touches[event_index] = event.position
				
			if active_touches.size() == 1:
				# Single touch: Drag logic
				position += event.position - drag_offset_start
				var p = get_parent()
				if p is Control:
					var min_pos = Vector2.ZERO
					var max_pos = p.size - (size * scale)
					position = position.clamp(min_pos, max_pos)
				accept_event()
			elif active_touches.size() == 2:
				# Multi-touch: CONSUME but don't handle locally
				accept_event()
		return # Block normal input

	if event is InputEventScreenDrag or event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT)):
		if (event is InputEventScreenTouch and not event.pressed) or (event is InputEventMouseButton and not event.pressed):
			update_dir(Vector2i.ONE)
		else:
			var vec: Vector2 = event.position - center_offset
			var threshold = SHIFT.x * 0.4
			
			# 1. Deadzone Check
			if vec.length() < threshold:
				update_dir(Vector2i.ONE)
				return

			# 2. Determine Raw Direction based on signs
			var dir = Vector2i.ONE
			if vec.x < -threshold: dir.x = 0
			elif vec.x > threshold: dir.x = 2
			
			if vec.y < -threshold: dir.y = 0
			elif vec.y > threshold: dir.y = 2
			
			# 3. Diagonal Suppression (Ratio Logic)
			# If one axis is much stronger than the other, snap to cardinal
			if dir.x != 1 and dir.y != 1:
				var abs_x = abs(vec.x)
				var abs_y = abs(vec.y)
				var ratio = min(abs_x, abs_y) / max(abs_x, abs_y)
				
				# Threshold 0.6 = approx 31 degrees (Even wider cardinal zone)
				# Increasing this makes diagonals HARDER to hit (must be more precise)
				if ratio < 0.6:
					# Suppress the weaker axis
					if abs_x > abs_y:
						dir.y = 1 # Snap to Horizontal
					else:
						dir.x = 1 # Snap to Vertical

			update_dir(dir)

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_MOUSE_EXIT:
		update_dir(Vector2i.ONE)
