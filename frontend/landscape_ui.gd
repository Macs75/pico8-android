extends Control

var tex_x_normal = preload("res://assets/btn_x_normal.png")
var tex_x_pressed = preload("res://assets/btn_x_pressed.png")
var tex_o_normal = preload("res://assets/btn_o_normal.png")
var tex_o_pressed = preload("res://assets/btn_o_pressed.png")

var tex_mouse_l_normal = preload("res://assets/btn_mouse_left_normal.png")
var tex_mouse_l_pressed = preload("res://assets/btn_mouse_left_pressed.png")
var tex_mouse_r_normal = preload("res://assets/btn_mouse_right_normal.png")
var tex_mouse_r_pressed = preload("res://assets/btn_mouse_right_pressed.png")

var tex_esc_normal = preload("res://assets/btn_esc_normal.png")
var tex_esc_pressed = preload("res://assets/btn_esc_pressed.png")
var tex_power_normal = preload("res://assets/btn_poweroff_normal.png")
var tex_power_pressed = preload("res://assets/btn_poweroff_pressed.png")

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

func _on_intent_session_started():
	var esc_btn = get_node_or_null("Control/SystemButtons/Escape")
	if esc_btn:
		esc_btn.set_textures(tex_power_normal, tex_power_pressed)
		if "key_id" in esc_btn:
			esc_btn.key_id = "IntentExit"
			
		if esc_btn.has_method("set_cap_text"):
			esc_btn.cap_text = ""
		elif "text" in esc_btn:
			esc_btn.text = ""

func _process(delta: float) -> void:
	var arranger = get_node_or_null("../Arranger")
	if arranger:
		# Always update scale to ensure synchronization with Arranger
		# Force uniform scaling to prevent distortion (use X scale for both axes)
		var s = arranger.scale.x
		scale = Vector2(s, s)
		# Compensate size so anchors cover the full viewport in local coordinates
		size = get_viewport_rect().size / s
		
		# Inverse scale the high-res D-Pad so it stays physical size
		var dpad = get_node_or_null("Control/LeftPad/Omnipad")
		if dpad:
			var target_scale = 8.5 / s
			dpad.scale = Vector2(target_scale, target_scale)
	else:
		size = get_viewport_rect().size

	var is_landscape = PicoVideoStreamer.is_system_landscape()
	var should_be_visible = is_landscape and not ControllerUtils.is_real_controller_connected()
	
	visible = should_be_visible

func _update_buttons_for_mode(is_trackpad: bool):
	var x_btn = get_node_or_null("Control/RightPad/X")
	var z_btn = get_node_or_null("Control/RightPad/Z")
	
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
