extends Control

var tex_mouse_l_normal = preload("res://assets/btn_mouse_left_normal.png")
var tex_mouse_l_pressed = preload("res://assets/btn_mouse_left_pressed.png")
var tex_mouse_r_normal = preload("res://assets/btn_mouse_right_normal.png")
var tex_mouse_r_pressed = preload("res://assets/btn_mouse_right_pressed.png")

var tex_power_normal = preload("res://assets/btn_poweroff_normal.png")
var tex_power_pressed = preload("res://assets/btn_poweroff_pressed.png")

@onready var arranger = get_node_or_null("../Arranger")
@onready var dpad = get_node_or_null("Control/LeftPad/dpad")
@onready var x_btn = get_node_or_null("Control/RightPad/X")
@onready var z_btn = get_node_or_null("Control/RightPad/O")
@onready var esc_btn = get_node_or_null("Control/SystemButtons/Escape")
@onready var chip_l = get_node_or_null("kb_pocketchip_left")
@onready var chip_r = get_node_or_null("kb_pocketchip_right")

func _ready() -> void:
	# LandscapeUI is a child of Main (where PicoVideoStreamer script is attached)
	var streamer = get_parent()
	if streamer.has_signal("input_mode_changed"):
		streamer.input_mode_changed.connect(_update_buttons_for_mode)
		# Initialize buttons with current state
		_update_buttons_for_mode(streamer.get_input_mode() == streamer.InputMode.TRACKPAD)

	# Connect to RunCmd for Intent Session updates
	var runcmd = streamer.get_node_or_null("runcmd")
	if runcmd:
		if not runcmd.intent_session_started.is_connected(_on_intent_session_started):
			runcmd.intent_session_started.connect(_on_intent_session_started)
		# Check if already started (late join)
		if runcmd.is_intent_session:
			_on_intent_session_started()
			
	# Optimize: Listen for resize instead of polling
	get_tree().root.size_changed.connect(_on_resize)
	
	if streamer:
		if streamer.has_signal("layout_reset"):
			streamer.layout_reset.connect(_on_layout_reset)
			
	# Initial Layout
	_on_resize()

func _on_layout_reset(_is_landscape: bool):
	# Even if it's not our orientation, we might need to reset dirty state
	_on_resize()

func _on_intent_session_started():
	if esc_btn:
		esc_btn.set_textures(tex_power_normal, tex_power_pressed)
		if "key_id" in esc_btn:
			esc_btn.key_id = "IntentExit"
			
		if esc_btn.has_method("set_cap_text"):
			esc_btn.cap_text = ""
		elif "text" in esc_btn:
			esc_btn.text = ""

func _on_resize():
	if arranger:
		# Always update scale to ensure synchronization with Arranger
		# Force uniform scaling to prevent distortion (use X scale for both axes)
		var s = arranger.scale.x
		scale = Vector2(s, s)
		# Compensate size so anchors cover the full viewport in local coordinates
		size = get_viewport_rect().size / s
		
	else:
		size = get_viewport_rect().size

	var is_landscape = PicoVideoStreamer.is_system_landscape()
	var mode = PicoVideoStreamer.get_controls_mode()
	var should_be_visible = true
	
	if mode == PicoVideoStreamer.ControlsMode.DISABLED:
		should_be_visible = false
	elif mode == PicoVideoStreamer.ControlsMode.FORCE:
		should_be_visible = true
	else: # AUTO
		should_be_visible = not arranger.cached_controller_connected
	
	if is_landscape:
		if chip_l:
			var saved_pos_l = PicoVideoStreamer.get_control_pos("kb_pocketchip_left", is_landscape)
			if saved_pos_l == null:
				chip_l.position.x = 0 # Flush left
				chip_l.position.y = (size.y / 2.0) - (chip_l.size.y / 2.0)
			else:
				chip_l.position = saved_pos_l
				var saved_scale_l = PicoVideoStreamer.get_control_scale("kb_pocketchip_left", is_landscape)
				if "original_scale" in chip_l:
					chip_l.scale = chip_l.original_scale * saved_scale_l
		
		if chip_r:
			var saved_pos_r = PicoVideoStreamer.get_control_pos("kb_pocketchip_right", is_landscape)
			if saved_pos_r == null:
				# kb_pocketchip_right is anchored to the top-right
				# To make it flush with the right edge, we set X to parent's width minus control's width.
				chip_r.position = Vector2(size.x - chip_r.size.x, (size.y / 2.0) - (chip_r.size.y / 2.0))
			else:
				chip_r.position = saved_pos_r
				var saved_scale_r = PicoVideoStreamer.get_control_scale("kb_pocketchip_right", is_landscape)
				if "original_scale" in chip_r:
					chip_r.scale = chip_r.original_scale * saved_scale_r
	
	visible = should_be_visible

func _process(_delta: float) -> void:
	if arranger and arranger.dirty:
		_on_resize()


func _update_buttons_for_mode(_is_trackpad: bool):
	# if is_	:
	# 	if x_btn:
	# 		x_btn.set_textures(tex_mouse_l_normal, tex_mouse_l_pressed)
	# 	if z_btn:
	# 		z_btn.set_textures(tex_mouse_r_normal, tex_mouse_r_pressed)
	# else:
	if x_btn:
		# Use button's own textures (may be custom or default)
		x_btn.set_textures(x_btn.texture_normal, x_btn.texture_pressed)
	if z_btn:
		# Use button's own textures (may be custom or default)
		z_btn.set_textures(z_btn.texture_normal, z_btn.texture_pressed)
