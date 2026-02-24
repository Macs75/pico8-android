extends PanelContainer
class_name SploreCartItem

signal item_action(item_node)

var item_data: Dictionary = {}
var is_selected: bool = false

@onready var label_name: Label = %LabelName
@onready var label_author: Label = %LabelAuthor
@onready var checkbox_label: Label = %CheckboxLabel

func _ready():
	focus_entered.connect(_update_style.bind(true))
	focus_exited.connect(_update_style.bind(false))
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
	custom_minimum_size.y = font_size * 2.5

func _update_checkbox():
	checkbox_label.text = "☑" if is_selected else "☐"

func _update_style(focused: bool = false):
	_update_checkbox()
	
	var style = get_theme_stylebox("panel", "PanelContainer")
	if not style: return
	
	style = style.duplicate()
	
	var selected_color = Color(0.6, 1.0, 0.6) # PICO-8 Pale Green
	var focus_color = Color(0.3, 0.6, 1.0) # PICO-8 Sky Blue
	
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
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		item_action.emit(self)
		get_viewport().set_input_as_handled()

func _toggle_selected():
	is_selected = not is_selected
	_update_style(has_focus())
