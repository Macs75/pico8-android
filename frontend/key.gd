extends NinePatchRect

enum KeycapType {TEXT, HEX, NONE}
enum FontType {NORMAL, WIDE, WIDE_W_SHIFT, SMALL, CUSTOM, CUSTOM_SMALL}
enum SpecialBehaviour {NONE, LTRKEY}
static var font_normal = preload("res://assets/font/atlas-0.png") as FontFile
static var font_wide = preload("res://assets/font/atlas.png") as FontFile
static var font_custom = preload("res://assets/font_custom.png") as FontFile

static var keycap_normal = preload("res://assets/keycap.png")
static var keycap_held = preload("res://assets/keycap_pressed.png")
static var keycap_locked = preload("res://assets/keycap_locked.png")

@export var key_id: String = "Left"
@export var key_id_shift_override: String = ""
@export var cap_type: KeycapType = KeycapType.TEXT
@export_multiline var cap_text: String = "a"
@export var cap_type_shift: KeycapType = KeycapType.NONE
@export var cap_text_shift: String = "A"
@export var font_type: FontType = FontType.NORMAL
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
var drag_offset_start: Vector2
var is_repositionable: bool = true

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
		if event is InputEventScreenTouch:
			if event.pressed:
				drag_offset_start = event.position
				accept_event()
			else:
				# Save position when drag ends
				_save_position()
				accept_event()
		elif event is InputEventScreenDrag:
			position += event.position - drag_offset_start
			
			# Clamp to parent
			var p = get_parent()
			if p is Control:
				var min_pos = Vector2.ZERO
				var max_pos = p.size - size
				position = position.clamp(min_pos, max_pos)
			
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
				_update_visuals()
			elif key_state == KeyState.LOCKED:
				key_state = KeyState.HELD
				repeat_timer = INF
				_update_visuals()
		elif key_state == KeyState.HELD:
			key_state = KeyState.RELEASED
			send_ev(false)
			_update_visuals()

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
		cap_text_shift = String.chr(cap_text.to_ascii_buffer()[0] + 31)
	elif cap_type_shift == KeycapType.HEX:
		cap_text_shift = cap_text_shift.hex_decode().get_string_from_ascii()
	elif cap_type_shift == KeycapType.NONE:
		cap_text_shift = cap_text
		
	if texture_normal and key_state == KeyState.RELEASED:
		self.texture = texture_normal
		self.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		%Label.visible = false
	elif texture_pressed and key_state == KeyState.HELD:
		self.texture = texture_pressed
		self.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		%Label.visible = false
	
	_update_visuals()
	
	# --- Drag & Drop Init ---
	original_position = position
	PicoVideoStreamer.instance.layout_reset.connect(_on_layout_reset)
	
	# Attempt to load saved position
	var is_landscape = _is_in_landscape_ui()
	
	# Restrict repositioning for specific containers (e.g. PocketCHIP layout)
	var p = get_parent()
	if p and p.name == "kb_pocketchip":
		is_repositionable = false
		
	if is_repositionable:
		var saved_pos = PicoVideoStreamer.get_control_pos(name, is_landscape)
		if saved_pos != null:
			position = saved_pos

func _is_in_landscape_ui() -> bool:
	# heuristic: check if we are inside LandscapeUI node path
	var p = get_parent()
	while p:
		if p.name == "LandscapeUI":
			return true
		p = p.get_parent()
	return false

func _save_position():
	PicoVideoStreamer.set_control_pos(name, position, _is_in_landscape_ui())

func _on_layout_reset(target_is_landscape: bool):
	if target_is_landscape == _is_in_landscape_ui():
		position = original_position

func set_textures(new_normal: Texture2D, new_pressed: Texture2D):
	texture_normal = new_normal
	texture_pressed = new_pressed
	
	# Immediate Visual Refresh
	if key_state == KeyState.RELEASED:
		self.texture = texture_normal if texture_normal else keycap_normal
	elif key_state == KeyState.HELD:
		self.texture = texture_pressed if texture_pressed else keycap_held
	_update_visuals()

var last_shift_state := false

func _process(delta: float) -> void:
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
	var shift_held = "Shift" in PicoVideoStreamer.instance.held_keys
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
		
	# Update Font settings
	var myrect = self.get_rect().size / 2
	var lblrect = %Label.get_rect().size

	var regular_font_on = (
		(font_type != FontType.WIDE)
		and (font_type != FontType.CUSTOM)
		and (font_type != FontType.CUSTOM_SMALL)
		and (font_type != FontType.WIDE_W_SHIFT or not shift_held)
	)
	var small_font_on = (not regular_font_on or font_type == FontType.SMALL) and font_type != FontType.CUSTOM
	
	if regular_font_on:
		%Label.label_settings.font = font_normal
	elif font_type == FontType.CUSTOM or font_type == FontType.CUSTOM_SMALL:
		%Label.label_settings.font = font_custom
	else:
		%Label.label_settings.font = font_wide
	
	if small_font_on:
		%Label.label_settings.font_size = 5
	else:
		%Label.label_settings.font_size = 10
		
	# Calculate Position
	var pos = (myrect - lblrect) / 2
	
	if regular_font_on:
		pos += Vector2(0.5, -1)
	else:
		pos += Vector2(0, -1)
		
	if key_state != KeyState.RELEASED:
		pos += Vector2(0, 1)
		
	%Label.position = pos.round()
		
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if key_state != KeyState.RELEASED:
			key_state = KeyState.RELEASED
			send_ev(false)
			self.texture = texture_normal if texture_normal else keycap_normal
			_update_visuals()
