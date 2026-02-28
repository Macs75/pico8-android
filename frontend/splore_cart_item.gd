extends PanelContainer
class_name SploreCartItem

signal item_action(item_node)

var item_data: Dictionary = {}
var is_selected: bool = false

@onready var label_name: Label = %LabelName
@onready var label_author: Label = %LabelAuthor
@onready var checkbox_label: Label = %CheckboxLabel
@onready var info_margin: MarginContainer = %InfoMargin
@onready var open_bbs_button: Button = %OpenBbsButton

var _press_start_time: int = 0
var _press_start_pos: Vector2 = Vector2.ZERO
const SHORT_PRESS_THRESHOLD_MS = 400
const MOVE_THRESHOLD = 25.0

func _ready():
	focus_entered.connect(_update_style.bind(true))
	focus_exited.connect(_update_style.bind(false))
	open_bbs_button.pressed.connect(_on_bbs_pressed)
	_update_style(false)

func setup(data, _index: int):
	item_data = data if data is Dictionary else {}
	label_name.text = item_data.get("title", "Unknown")
	label_author.text = item_data.get("author", "")
	_update_style(has_focus())

func set_font_size(font_size: int):
	label_name.add_theme_font_size_override("font_size", font_size)
	label_author.add_theme_font_size_override("font_size", int(font_size * 0.85))
	checkbox_label.add_theme_font_size_override("font_size", int(font_size * 1.2))
	
	var vertical_margin = int(font_size * 0.5)
	info_margin.add_theme_constant_override("margin_top", vertical_margin)
	info_margin.add_theme_constant_override("margin_bottom", vertical_margin)
	info_margin.add_theme_constant_override("margin_right", int(font_size * 0.5))
	
	custom_minimum_size.y = font_size * 2.5
	open_bbs_button.add_theme_font_size_override("font_size", int(font_size * 1.2))

func _update_checkbox():
	checkbox_label.text = "☑︎" if is_selected else "⬜"

func _update_style(focused: bool = false):
	_update_checkbox()
	
	var style = get_theme_stylebox("panel", "PanelContainer")
	if not style: return
	
	style = style.duplicate()
	
	var selected_color = Color(0.6, 1.0, 0.6) # PICO-8 Pale Green
	var focus_color = Color(0.442, 0.479, 1.0, 1.0) # PICO-8 Sky Blue
	
	var name_color = Color(1, 1, 1, 1)
	var border_color = Color(0, 0, 0, 0)
	var border_width = 0

	if focused:
		border_width = 2
		border_color = focus_color
		name_color = focus_color
	elif is_selected:
		border_width = 2
		border_color = selected_color
		name_color = selected_color

	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width if border_width > 0 else 1
	
	if border_width > 0:
		style.border_color = border_color
	else:
		style.border_color = Color(0.22, 0.22, 0.22, 0.8)

	var check_color = Color(1, 1, 1, 1)
	if focused:
		check_color = focus_color
	elif is_selected:
		check_color = selected_color

	add_theme_stylebox_override("panel", style)
	label_name.add_theme_color_override("font_color", name_color)
	checkbox_label.add_theme_color_override("font_color", check_color)

func _gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_start_time = Time.get_ticks_msec()
			_press_start_pos = event.global_position
		else:
			if _press_start_time > 0:
				var duration = Time.get_ticks_msec() - _press_start_time
				var distance = event.global_position.distance_to(_press_start_pos)
				
				# Trigger only on a proper "short press" (tap)
				# and ensure it wasn't a drag/scroll (distance check)
				if duration < SHORT_PRESS_THRESHOLD_MS and distance < MOVE_THRESHOLD:
					item_action.emit.call_deferred(self )
				
				_press_start_time = 0

	elif event is InputEventJoypadButton:
		var button_to_check = PicoVideoStreamer.get_confirm_button()
		if event.pressed and (event.button_index == button_to_check):
			item_action.emit.call_deferred(self )
			get_viewport().set_input_as_handled()

func _toggle_selected():
	is_selected = not is_selected
	_update_style(has_focus())

func _on_bbs_pressed():
	var pid = item_data.get("id", item_data.get("post_id", ""))
	if pid == "":
		return
		
	var url = "https://www.lexaloffle.com/bbs/?pid=%s" % str(pid)
	OS.shell_open.call_deferred(url)
