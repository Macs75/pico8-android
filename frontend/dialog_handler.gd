extends Control

var cancel_callback: Callable

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
		
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JoyButton.JOY_BUTTON_A:
			var focus = get_viewport().gui_get_focus_owner()
			if focus and is_ancestor_of(focus) and focus is BaseButton:
				focus.pressed.emit()
				get_viewport().set_input_as_handled()
				
		elif event.button_index == JoyButton.JOY_BUTTON_B:
			if cancel_callback.is_valid():
				cancel_callback.call()
			else:
				# Fallback: find a close/cancel button or just close
				queue_free()
			get_viewport().set_input_as_handled()
