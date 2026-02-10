extends ColorRect

func setup(data: Dictionary):
	# data: { title, author, sub_carts: { filename: { seconds, launches } } }
	var font_size = data.get("font_size", 12)
	var title_val = data.get("title", "Unknown Cart")
	if title_val == null: title_val = "Unknown Cart"
	%Title.text = str(title_val)
	
	var author_val = data.get("author", "Unknown")
	if author_val == null: author_val = "Unknown"
	%Author.text = "by " + str(author_val)
	%Title.add_theme_font_size_override("font_size", int(font_size * 1.1))
	%Author.add_theme_font_size_override("font_size", int(font_size * 0.9))
	%CloseButton.add_theme_font_size_override("font_size", font_size)
	
	# Clear list
	for child in %ListContainer.get_children():
		child.queue_free()
		
	var subs = data.get("sub_carts", {})
	if subs.is_empty():
		var lbl = Label.new()
		lbl.text = "No detailed stats available."
		lbl.add_theme_font_size_override("font_size", font_size)
		%ListContainer.add_child(lbl)
		return
		
	# Sort filenames?
	var filenames = []
	if typeof(subs) == TYPE_ARRAY:
		filenames = subs
	else:
		filenames = subs.keys()
		
	filenames.sort()
	
	for fname in filenames:
		var hbox = HBoxContainer.new()
		
		var name_lbl = Label.new()
		name_lbl.text = fname.get_basename() + " "
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", int(font_size * 0.8))
		
		var info_lbl = Label.new()
		var stat = subs[fname]
		info_lbl.text = "%s|%d" % [_fmt_time(stat.seconds), stat.launches]
		info_lbl.add_theme_font_size_override("font_size", int(font_size * 0.6))
		
		hbox.add_child(name_lbl)
		hbox.add_child(info_lbl)
		
		%ListContainer.add_child(hbox)
		
	%CloseButton.grab_focus()

func _on_close_pressed():
	queue_free()

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		queue_free()
		get_viewport().set_input_as_handled()

func _fmt_time(total_seconds: int) -> String:
	var h = total_seconds / 3600
	var m = (total_seconds % 3600) / 60
	var s = total_seconds % 60
	if h > 0:
		return "%dh:%02dm" % [h, m]
	return "%02dm:%02ds" % [m, s]
