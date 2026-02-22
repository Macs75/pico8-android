extends NinePatchRect

enum KeycapType {TEXT, HEX, NONE}
enum FontType {NORMAL, WIDE, WIDE_W_SHIFT, SMALL, CUSTOM, CUSTOM_SMALL}
enum SpecialBehaviour {NONE, LTRKEY}
static var font_normal = preload("res://assets/font/Pico8-Keyboard-RegularV1.otf") as FontFile
static var font_wide = preload("res://assets/font/Pico8-Keyboard-RegularV1.otf") as FontFile
static var font_custom = preload("res://assets/font/NotoEmoji-Regular.ttf") as FontFile

static var keycap_normal = preload("res://assets/keycap.png")
static var keycap_held = preload("res://assets/keycap_pressed.png")
static var keycap_locked = preload("res://assets/key_locked.png")

const CustomControlTextures = preload("res://custom_control_textures.gd")

@export var key_id: String = "Left"
@export var key_id_shift_override: String = ""
@export var cap_type: KeycapType = KeycapType.TEXT
@export_multiline var cap_text: String = "a"
@export var cap_type_shift: KeycapType = KeycapType.NONE
@export var cap_text_shift: String = "A"
@export var font_type: FontType = FontType.NORMAL
@export var font_color: Color = Color(0.105882354, 0.16862746, 0.30980393, 1)
@export var can_lock: bool = false
@export var unicode: bool = true
@export var unicode_override: String = ""
@export var shift_unicode_override: String = ""
@export var special_behaviour: SpecialBehaviour = SpecialBehaviour.NONE
@export var texture_normal: Texture2D = null
@export var texture_pressed: Texture2D = null

enum KeyState {RELEASED, HELD, LOCKED}

var key_state = KeyState.RELEASED
var repeat_timer = 0
const REPEAT_TIME_FIRST = 350
const REPEAT_TIME_AFTER = 150

var original_position: Vector2
var original_scale: Vector2
var editor_scale: Vector2 # Base scale from editor/tscn
var drag_offset_start: Vector2
var is_repositionable: bool = true

var active_touches = {}
var initial_pinch_dist = 0.0
var initial_scale_modifier = 1.0

# Base Textures (Saved at startup for theme rollback)
var default_texture_normal: Texture2D = null
var default_texture_pressed: Texture2D = null

# Track if press effect is enabled (for custom textures without pressed variant)
var has_press_effect: bool = true

func send_ev(down: bool, echo: bool = false):
	var shifting = "Shift" in PicoVideoStreamer.instance.held_keys
	var unicode_id = 0
	if unicode:
		if shifting:
			unicode_id = (shift_unicode_override if shift_unicode_override else cap_text.to_upper()).to_ascii_buffer()[0]
		else:
			unicode_id = (unicode_override if unicode_override else cap_text.to_lower()).to_ascii_buffer()[0]
		# print("sending unicode " + String.chr(unicode_id))
	var id = key_id
	if key_id_shift_override and shifting:
		id = key_id_shift_override
	PicoVideoStreamer.instance.vkb_setstate(
		id, down,
		unicode_id,
		echo
	)
	#print("sending ", key_id, " as ", down)
	
func _gui_input(event: InputEvent) -> void:
	if PicoVideoStreamer.display_drag_enabled and is_repositionable:
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

	if event is InputEventScreenTouch or event is InputEventMouseButton:
		# print(event)
		if event.pressed:
			if key_state == KeyState.RELEASED:
				if can_lock and (event.double_tap if (event is InputEventScreenTouch) else event.double_click):
					key_state = KeyState.LOCKED
				else:
					key_state = KeyState.HELD
					repeat_timer = Time.get_ticks_msec() + REPEAT_TIME_FIRST
				send_ev(true)
				if has_press_effect: # Only update visuals if press effect enabled
					_update_visuals()
			elif key_state == KeyState.LOCKED:
				key_state = KeyState.HELD
				repeat_timer = INF
				if has_press_effect: # Only update visuals if press effect enabled
					_update_visuals()
		elif key_state == KeyState.HELD:
			key_state = KeyState.RELEASED
			send_ev(false)
			if has_press_effect: # Only update visuals if press effect enabled
				_update_visuals()

	if has_press_effect: # Only apply texture changes if press effect enabled
		match key_state:
			KeyState.RELEASED:
				self.texture = texture_normal if texture_normal else keycap_normal
			KeyState.HELD:
				self.texture = texture_pressed if texture_pressed else keycap_held
			KeyState.LOCKED:
				self.texture = keycap_locked

func _ready() -> void:
	if cap_type == KeycapType.HEX:
		cap_text = cap_text.hex_decode().get_string_from_ascii()
	elif cap_type == KeycapType.NONE:
		cap_text = ""
	if special_behaviour == SpecialBehaviour.LTRKEY:
		cap_text_shift = String.chr(cap_text.to_ascii_buffer()[0] + 75)
	elif cap_type_shift == KeycapType.HEX:
		cap_text_shift = cap_text_shift.hex_decode().get_string_from_ascii()
	elif cap_type_shift == KeycapType.NONE:
		cap_text_shift = cap_text
	
	# --- Drag & Drop Init ---
	original_position = position
	original_scale = scale
	editor_scale = scale
	
	# Cache Default Textures (Initial State from Scene)
	default_texture_normal = texture_normal
	default_texture_pressed = texture_pressed
	
	if PicoVideoStreamer.instance:
		PicoVideoStreamer.instance.layout_reset.connect(_on_layout_reset)
		PicoVideoStreamer.instance.bezel_layout_updated.connect(_on_bezel_layout_updated)
	
	# Attempt to load saved position
	var is_landscape = _is_in_landscape_ui()
	
	# Restrict repositioning for specific containers (e.g. PocketCHIP layout)
	var p = get_parent()
	if p and p.name.begins_with("kb_pocketchip"):
		is_repositionable = false
		
	if is_repositionable:
		var saved_pos = PicoVideoStreamer.get_control_pos(name, is_landscape)
		if saved_pos != null:
			position = saved_pos
		else:
			# Theme Layout Fallback (Startup Race Check)
			if PicoVideoStreamer.instance:
				var rect = PicoVideoStreamer.instance.get_current_bezel_rect()
				if rect.has_area():
					_on_bezel_layout_updated(rect, Vector2.ONE)
					
		var saved_scale = PicoVideoStreamer.get_control_scale(name, is_landscape)
		scale = original_scale * saved_scale
	
	# --- Custom Texture Loading ---
	var custom_loaded = _load_and_apply_custom_textures(is_landscape)
	
	# Only apply default textures if custom ones weren't loaded
	if not custom_loaded:
		if texture_normal and key_state == KeyState.RELEASED:
			self.texture = texture_normal
		elif texture_pressed and key_state == KeyState.HELD:
			self.texture = texture_pressed

		self.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		if p and not p.name.begins_with("kb_pocketchip"):
			%Label.visible = false
	
	if (%Label.visible):
		_update_visuals()

func _is_in_landscape_ui() -> bool:
	return LayoutHelper.is_in_landscape_ui(self)

func _save_layout():
	LayoutHelper.save_layout(self, original_scale.x)

func _on_layout_reset(target_is_landscape: bool):
	if is_visible_in_tree() and target_is_landscape == _is_in_landscape_ui():
		position = original_position
		scale = original_scale

func _on_bezel_layout_updated(bezel_rect: Rect2, _unused_scale: Vector2):
	if not is_repositionable: return
	LayoutHelper.apply_layout(self, bezel_rect)

func reload_textures():
	var is_landscape = _is_in_landscape_ui()
	
	# Reset state to RELEASED for clean reload if stuck
	if key_state != KeyState.RELEASED and key_state != KeyState.LOCKED:
		key_state = KeyState.RELEASED
	
	# Reset to defaults (Use cached defaults, not potentially tainted current vars)
	texture_normal = default_texture_normal
	texture_pressed = default_texture_pressed
	
	self.texture = texture_normal if texture_normal else keycap_normal
	has_press_effect = true # Reset assumption
	%Label.visible = true
	self.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	
	var custom_loaded = _load_and_apply_custom_textures(is_landscape)
			
	if not custom_loaded:
		# Restore original textures (Which are now the defaults)
		if texture_normal and key_state == KeyState.RELEASED:
			self.texture = texture_normal
			self.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			%Label.visible = false
		elif texture_pressed and key_state == KeyState.HELD:
			self.texture = texture_pressed
			self.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			%Label.visible = false
		else:
			# Fallback to keycaps
			_update_visuals() # This handles keycap_normal/held assignment
			
func reload_layout():
	if not is_repositionable: return
	
	var is_landscape = _is_in_landscape_ui()
	var user_pos = PicoVideoStreamer.get_control_pos(name, is_landscape)
	
	# 1. User Override
	if user_pos != null:
		# User override exists, respect it (or re-apply it)
		position = user_pos
		var saved_scale = PicoVideoStreamer.get_control_scale(name, is_landscape)
		scale = original_scale * saved_scale
		return
		
	# 2. Theme or Default
	var layout = ThemeManager.get_theme_layout(is_landscape)
	if layout.is_empty():
		# Restore Default
		position = original_position
		scale = original_scale
	else:
		# Apply Theme
		if PicoVideoStreamer.instance:
			var rect = PicoVideoStreamer.instance.get_current_bezel_rect()
			LayoutHelper.apply_layout(self, rect)


func _load_and_apply_custom_textures(is_landscape: bool) -> bool:
	var texture_name = _get_texture_name_for_button()
	if not texture_name:
		return false
		
	var custom_textures = CustomControlTextures.get_custom_textures(texture_name, is_landscape)
	if custom_textures[0] != null: # Has custom texture
		has_press_effect = (custom_textures[1] != null)
		%Label.visible = false
		set_textures(custom_textures[0], custom_textures[1])
		self.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		
		# Re-apply Aspect Ratio Logic
		var tex_size = custom_textures[0].get_size()
		if tex_size.x > 0 and tex_size.y > 0:
			var tex_aspect = tex_size.x / tex_size.y
			var btn_aspect = size.x / size.y if size.y > 0 else 1.0
			
			if abs(tex_aspect - btn_aspect) > 0.01:
				var area = size.x * size.y
				var new_width = sqrt(area * tex_aspect)
				var new_height = new_width / tex_aspect
				
				# Adjust scale to achieve new proportions
				scale.x = (new_width / size.x) * editor_scale.x
				scale.y = (new_height / size.y) * editor_scale.y
				# Update original_scale so reset preserves the aspect ratio
				original_scale = scale
				
		z_index = 150
		return true
		
	return false

func set_textures(new_normal: Texture2D, new_pressed: Texture2D):
	texture_normal = new_normal
	texture_pressed = new_pressed
	
	# Immediate Visual Refresh
	if key_state == KeyState.RELEASED:
		self.texture = texture_normal if texture_normal else keycap_normal
	elif key_state == KeyState.HELD:
		# If no pressed texture provided, use normal texture instead
		if texture_pressed:
			self.texture = texture_pressed
		else:
			self.texture = texture_normal if texture_normal else keycap_held
	_update_visuals()

func _get_texture_name_for_button() -> String:
	# Map node names to texture base names
	match name:
		"X": return "X"
		"O": return "O"
		"Escape": return "escape"
		"Pause": return "menu"
		_: return "" # Not a customizable button

var last_shift_state := false

func _process(_delta: float) -> void:
	# 1. Handle Key Repeats
	if key_state == KeyState.HELD and Time.get_ticks_msec() > repeat_timer:
		if can_lock:
			key_state = KeyState.LOCKED
			self.texture = keycap_locked
			_update_visuals()
		else:
			repeat_timer = Time.get_ticks_msec() + REPEAT_TIME_AFTER
			send_ev(true, true)
	
	# 2. Check for Shift Toggle
	var shift_held = false
	if PicoVideoStreamer.instance and "Shift" in PicoVideoStreamer.instance.held_keys:
		shift_held = true
	if shift_held != last_shift_state:
		last_shift_state = shift_held
		_update_visuals()

func _update_visuals() -> void:
	var shift_held = last_shift_state
	
	# Update Text
	if shift_held:
		%Label.text = cap_text_shift
	else:
		%Label.text = cap_text
		
	var regular_font_on = (
		(font_type != FontType.WIDE)
		and (font_type != FontType.CUSTOM)
		and (font_type != FontType.CUSTOM_SMALL)
		and (font_type != FontType.WIDE_W_SHIFT or not shift_held)
	)
	var small_font_on = font_type == FontType.SMALL and font_type != FontType.CUSTOM
	
	if regular_font_on:
		%Label.label_settings.font = font_normal
	elif font_type == FontType.CUSTOM or font_type == FontType.CUSTOM_SMALL:
		%Label.label_settings.font = font_custom
	else:
		%Label.label_settings.font = font_wide
	
	if small_font_on:
		%Label.label_settings.font_size = 25
	elif font_type == FontType.CUSTOM_SMALL:
		%Label.label_settings.font_size = 25
	else:
		%Label.label_settings.font_size = 42

	%Label.label_settings.font_color = font_color

	# Calculate Position
	# 1. Force Label to cover the entire Key area (taking scale into account)
	var target_label_size = self.get_rect().size / %Label.scale
	%Label.size = target_label_size
	
	# 2. Position at origin (0,0) horizontally
	var pos = Vector2.ZERO
	# Adjust vertical offset to center on the key face (higher up)
	# -1px Y offset looks correct for 11px height keys
	if font_type == FontType.CUSTOM_SMALL:
		pos.y = -1.0
	else:
		pos.x = 0.5
		pos.y = -1.0
		
	if key_state != KeyState.RELEASED:
		pos.y += 1.0
		
	%Label.position = pos
		
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if key_state != KeyState.RELEASED:
			key_state = KeyState.RELEASED
			send_ev(false)
			self.texture = texture_normal if texture_normal else keycap_normal
			_update_visuals()
