extends PanelContainer

@onready var button_test_label = %ResultLabel
@onready var axis_test_label = %ResultLabel2
@onready var key_test_label = %ResultLabel3
@onready var close_test_btn = %CloseTestBtn

var test_device_id: int = -1
var last_event_time: int = 0

func _ready() -> void:
	close_test_btn.pressed.connect(queue_free)
	get_tree().root.size_changed.connect(_fit_to_screen)
	call_deferred("_fit_to_screen")
	close_test_btn.grab_focus();

func setup(device_id: int) -> void:
	test_device_id = device_id
	button_test_label.text = "Waiting..."
	axis_test_label.text = ""
	key_test_label.text = ""
	last_event_time = 0

	var screen_size = get_viewport().get_visible_rect().size
	var font_size = clamp(int(min(screen_size.x, screen_size.y) * 0.05), 12, 24)

	button_test_label.add_theme_font_size_override("font_size", font_size)
	axis_test_label.add_theme_font_size_override("font_size", font_size)
	key_test_label.add_theme_font_size_override("font_size", font_size)

	var header = get_node_or_null("VBoxContainer/Header")
	if header: header.add_theme_font_size_override("font_size", font_size)

	var subheader = get_node_or_null("VBoxContainer/SubHeader")
	if subheader: subheader.add_theme_font_size_override("font_size", int(font_size * 0.8))

	call_deferred("_fit_to_screen")

func _fit_to_screen() -> void:
	var screen_size = get_viewport().get_visible_rect().size
	var current_size = size * scale
	var max_w = screen_size.x - 40
	var max_h = screen_size.y - 40

	if current_size.x > max_w or current_size.y > max_h:
		var ratio_w = max_w / size.x
		var ratio_h = max_h / size.y
		scale = Vector2.ONE * min(scale.x, min(ratio_w, ratio_h))

	position = (screen_size - size * scale) / 2.0

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag or event is InputEventMouse:
		return

	var is_key_event = event is InputEventKey
	if event.device != test_device_id and not is_key_event:
		return

	if last_event_time == 0:
		button_test_label.text = ""

	var now = Time.get_ticks_msec()
	var delta = now - last_event_time

	var _get_dev_name = func(id):
		if id in Input.get_connected_joypads():
			var n = Input.get_joy_name(id)
			return n.left(15) + ".." if n.length() > 15 else n
		return "Non-Joypad"

	if event is InputEventJoypadButton and event.pressed:
		last_event_time = now
		button_test_label.text = "JoyBtn %d->b%d [ID: %d - %s]" % [event.button_index, event.button_index, event.device, _get_dev_name.call(event.device)]
		if delta > 100:
			axis_test_label.text = ""
			key_test_label.text = ""

	elif event is InputEventJoypadMotion and abs(event.axis_value) > 0.5:
		last_event_time = now
		axis_test_label.text = "JoyAxis %d->a%d [ID: %d - %s]" % [event.axis, event.axis, event.device, _get_dev_name.call(event.device)]
		if delta > 100:
			button_test_label.text = ""
			key_test_label.text = ""

	elif event is InputEventKey:
		last_event_time = now
		key_test_label.text = "Key %d->%s [ID:%d - %s]" % [event.keycode, OS.get_keycode_string(event.keycode), event.device, _get_dev_name.call(event.device)]
		if delta > 100:
			button_test_label.text = ""
			axis_test_label.text = ""
