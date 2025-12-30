extends NinePatchRect

enum KeycapType { TEXT, HEX, NONE }
enum FontType { NORMAL, WIDE, WIDE_W_SHIFT, SMALL, CUSTOM, CUSTOM_SMALL }
enum SpecialBehaviour { NONE, LTRKEY }
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

enum KeyState { RELEASED, HELD, LOCKED }

var key_state = KeyState.RELEASED
var repeat_timer = 0
const REPEAT_TIME_FIRST = 350
const REPEAT_TIME_AFTER = 150

func send_ev(down: bool, echo: bool = false):
	var shifting = "Shift" in PicoVideoStreamer.instance.held_keys
	var unicode_id = 0
	if unicode:
		if shifting:
			unicode_id = (shift_unicode_override if shift_unicode_override else cap_text.to_upper()).to_ascii_buffer()[0]
		else:
			unicode_id = (unicode_override if unicode_override else cap_text.to_lower()).to_ascii_buffer()[0]
		print("sending unicode " + String.chr(unicode_id))
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
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		print(event)
		if event.pressed:
			if key_state == KeyState.RELEASED:
				if can_lock and (event.double_tap if (event is InputEventScreenTouch) else event.double_click):
					key_state = KeyState.LOCKED
				else:
					key_state = KeyState.HELD
					repeat_timer = Time.get_ticks_msec() + REPEAT_TIME_FIRST
				send_ev(true)
			elif key_state == KeyState.LOCKED:
				key_state = KeyState.HELD
				repeat_timer = INF
		elif key_state == KeyState.HELD:
			key_state = KeyState.RELEASED
			send_ev(false)

	match key_state:
		KeyState.RELEASED:
			self.texture = keycap_normal
		KeyState.HELD:
			self.texture = keycap_held
		KeyState.LOCKED:
			self.texture = keycap_locked

func _ready() -> void:
	if cap_type == KeycapType.HEX:
		cap_text = cap_text.hex_decode().get_string_from_ascii()
	elif cap_type == KeycapType.NONE:
		cap_text = ""
	if special_behaviour == SpecialBehaviour.LTRKEY:
		cap_text_shift = String.chr(cap_text.to_ascii_buffer()[0]+31)
	elif cap_type_shift == KeycapType.HEX:
		cap_text_shift = cap_text_shift.hex_decode().get_string_from_ascii()
	elif cap_type_shift == KeycapType.NONE:
		cap_text_shift = cap_text

func _process(delta: float) -> void:
	var shift_held = "Shift" in PicoVideoStreamer.instance.held_keys
	if key_state == KeyState.HELD and Time.get_ticks_msec() > repeat_timer:
		if can_lock:
			key_state = KeyState.LOCKED
			self.texture = keycap_locked
		else:
			repeat_timer = Time.get_ticks_msec() + REPEAT_TIME_AFTER
			send_ev(true, true)
		#self.modulate = self.modulate.inverted()
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
	var small_font_on = (not regular_font_on or font_type == FontType.SMALL) and font_type != FontType.CUSTOM
	if regular_font_on:
		%Label.label_settings.font = font_normal
	elif font_type == FontType.CUSTOM or font_type == FontType.CUSTOM_SMALL:
		%Label.label_settings.font = font_custom
	else:
		%Label.label_settings.font = font_wide
	
	%Label.label_settings.font_color = Color(0, 0, 0, 1) # Force BLACK color
	
	if small_font_on:
		%Label.label_settings.font_size = 5
	else:
		%Label.label_settings.font_size = 10
		
	# Anchor-Based Centering (Robust)
	# Force Label to match Button size logic
	%Label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	# Force Alignment (just in case)
	%Label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	%Label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
	# Set Pivot to center so scale (0.5) keeps it centered
	%Label.pivot_offset = %Label.size / 2
	
	# Remove manual nudges - rely on pure centering
	# But shift slightly LEFT (-1) to account for button shadow/3D depth
	%Label.position += Vector2(-1, 0)
	
	if key_state != KeyState.RELEASED:
		%Label.position += Vector2(0, 1)
		
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if key_state != KeyState.RELEASED:
			key_state = KeyState.RELEASED
			send_ev(false)
			self.texture = keycap_normal
