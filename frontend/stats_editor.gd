extends "res://list_editor_base.gd"
class_name StatsEditor

var item_scene = preload("res://favourites_item.tscn")
const ActivityLogAnalyzerScript = preload("res://activity_log_analyzer.gd")
const FavouritesManagerScript = preload("res://favourites_manager.gd")
var detail_window_scene = preload("res://stats_detail_window.tscn")

var _cached_metadata: Dictionary = {}

@onready var btn_reset = %BtnReset

func _ready():
	super._ready()
	
	btn_reset.pressed.connect(_on_reset_pressed)
	btn_reset.gui_input.connect(_on_explicit_gui_input.bind(btn_reset))

func _setup_sort_options():
	option_sort.clear()
	# No Manual/Author
	option_sort.add_item("Name", 1)
	option_sort.add_item("Launches", 3)
	option_sort.add_item("Play Time", 4)
	
	# Default to Play Time
	option_sort.selected = 2
	is_ascending = false

class StatItem extends RefCounted:
	var name: String = ""
	var author: String = ""
	var cart_id: String = ""
	var filename: String = ""
	var is_stat_item: bool = true
	var _sort_seconds: int = 0
	var _sort_launches: int = 0
	var base_key: String = ""
	var sub_carts: Dictionary = {}

func _load_items_from_source() -> Array:
	var loaded_items = []
	var data = ActivityLogAnalyzer.cached_data
	_cached_metadata = MetadataCache.cached_metadata
	
	if data.has("carts"):
		for key in data.carts:
			var entry = data.carts[key]
			var name_clean = key
			
			if _cached_metadata.has(key):
				var meta = _cached_metadata[key]
				if meta.get("title") != null and not meta.title.is_empty():
					name_clean = meta.title

			var e_sec = int(entry.get("seconds", 0))
			var e_launch = int(entry.get("launches", 0))
			
			var time_fmt = activity_time_fmt(e_sec)
			var stats_str = "%s|%3d" % [time_fmt, e_launch]
			
			var is_bbs = key.is_valid_int()
			var rep_filename = entry.sub_carts.keys()[0] if entry.has("sub_carts") and entry.sub_carts.size() > 0 else key
			var item_cart_id = key if is_bbs else rep_filename.get_basename().get_basename()
			
			var item = StatItem.new()
			item.name = name_clean
			item.author = stats_str
			item.cart_id = item_cart_id
			item.filename = rep_filename
			item.is_stat_item = true
			item._sort_seconds = e_sec
			item._sort_launches = e_launch
			item.base_key = key
			if entry.has("sub_carts"):
				item.sub_carts = entry.sub_carts
			
			loaded_items.append(item)
	return loaded_items

func activity_time_fmt(total_seconds: int) -> String:
	var h = int(total_seconds / 3600.0)
	var m = int((total_seconds % 3600) / 60.0)
	var s = total_seconds % 60
	if h > 0:
		return "%dh:%02dm" % [h, m]
	return "%02dm:%02ds" % [m, s]

func _apply_sort():
	var get_sort_val = func(item: StatItem, property: String):
		match property:
			"Name": return str(item.name).to_lower()
			"Launches": return item._sort_launches
			"Play Time": return item._sort_seconds
		return ""

	var asc = is_ascending

	match option_sort.get_item_text(option_sort.selected):
		"Name":
			_all_items.sort_custom(func(a, b):
				var sort_val_a = get_sort_val.call(a, "Name")
				var sort_val_b = get_sort_val.call(b, "Name")
				if sort_val_a == sort_val_b:
					var p_a = get_sort_val.call(a, "Play Time")
					var p_b = get_sort_val.call(b, "Play Time")
					if asc:
						return p_a < p_b
					else:
						return p_a > p_b
				if asc:
					return sort_val_a < sort_val_b
				else:
					return sort_val_a > sort_val_b
			)
		"Launches":
			_all_items.sort_custom(func(a, b):
				var sort_val_a = get_sort_val.call(a, "Launches")
				var sort_val_b = get_sort_val.call(b, "Launches")
				if sort_val_a == sort_val_b:
					return get_sort_val.call(a, "Name") < get_sort_val.call(b, "Name")
				if asc:
					return sort_val_a < sort_val_b
				else:
					return sort_val_a > sort_val_b
			)
		"Play Time":
			_all_items.sort_custom(func(a, b):
				var sort_val_a = get_sort_val.call(a, "Play Time")
				var sort_val_b = get_sort_val.call(b, "Play Time")
				if sort_val_a == sort_val_b:
					return get_sort_val.call(a, "Name") < get_sort_val.call(b, "Name")
				if asc:
					return sort_val_a < sort_val_b
				else:
					return sort_val_a > sort_val_b
			)

func _instantiate_item(_item_data, _index: int) -> Control:
	var item_node = item_scene.instantiate()
	
	# Disable drag handle
	item_node.drag_enabled = false
	
	if not item_node.is_node_ready() and not item_node.is_inside_tree():
		# The node isn't ready yet to find Content/DragHandle, wait for it or set a param
		# Since we instantiate it, we can modify it after _ready or in setup. 
		# `setup` will be called by `list_editor_base.gd`
		pass

	if not item_node.item_long_pressed.is_connected(_on_item_long_pressed):
		item_node.item_long_pressed.connect(_on_item_long_pressed)
		
	return item_node

func _connect_item_signals(item_node):
	super._connect_item_signals(item_node)
	
	# Now that it's added to tree, we can safely hide the drag handle
	var drag_handle = item_node.get_node_or_null("Content/DragHandle")
	if drag_handle:
		drag_handle.visible = false

func _get_background_image_path(item_data) -> String:
	var base_path = FavouritesManagerScript.PICO8_DATA_PATH
	var cart_id = item_data.get("cart_id", "") if item_data is Dictionary else (item_data.cart_id if "cart_id" in item_data else "")
	var filename = item_data.get("filename", "") if item_data is Dictionary else (item_data.filename if "filename" in item_data else "")
	
	if not String(cart_id).is_empty():
		var subfolder = "carts"
		if String(cart_id).is_valid_int():
			if String(cart_id).length() >= 5:
				subfolder = String(cart_id)[0]
			else:
				subfolder = "0"
		return base_path + "/bbs/" + subfolder + "/" + str(cart_id) + ".p8.png"
	elif not String(filename).is_empty():
		return base_path + "/carts/" + str(filename)
	return ""

func _apply_subclass_footer_sizes(_size: int):
	btn_reset.add_theme_font_size_override("font_size", _size)

func _apply_subclass_static_focus():
	option_sort.focus_neighbor_left = btn_close.get_path()
	btn_close.focus_neighbor_right = btn_reset.get_path()
	btn_close.focus_neighbor_bottom = option_sort.get_path()
	btn_reset.focus_neighbor_left = btn_close.get_path()
	btn_reset.focus_neighbor_right = option_sort.get_path()
	btn_reset.focus_neighbor_bottom = option_sort.get_path()

func _apply_empty_list_boundary_focus():
	option_sort.focus_neighbor_bottom = btn_reset.get_path()
	btn_asc_desc.focus_neighbor_bottom = btn_close.get_path()
	btn_asc_desc.focus_neighbor_right = btn_close.get_path()
	btn_close.focus_neighbor_top = option_sort.get_path()
	btn_close.focus_neighbor_left = btn_asc_desc.get_path()
	btn_reset.focus_neighbor_top = option_sort.get_path()

func _apply_subclass_boundary_focus(last_item: Control):
	btn_close.focus_neighbor_top = last_item.get_path()
	btn_close.focus_neighbor_left = last_item.get_path()
	btn_reset.focus_neighbor_top = last_item.get_path()

func _on_reset_pressed():
	if has_node("CustomConfirmDialog"):
		return
		
	var confirm_cb = func():
		var dialog = get_node_or_null("CustomConfirmDialog")
		if dialog: dialog.queue_free()
		
		if FileAccess.file_exists(ActivityLogAnalyzerScript.STATS_FILE):
			DirAccess.remove_absolute(ActivityLogAnalyzerScript.STATS_FILE)
		
		# Reset Data
		ActivityLogAnalyzerScript.cached_data = {"last_analyzed_time": 0, "carts": {}}
		_all_items.clear()
		_refresh_list()
			
		if is_instance_valid(btn_reset):
			btn_reset.grab_focus()

	var cancel_cb = func():
		var dialog = get_node_or_null("CustomConfirmDialog")
		if dialog: dialog.queue_free()
		if is_instance_valid(btn_reset):
			btn_reset.grab_focus()

	UIUtils.create_confirm_dialog(
		self,
		"Confirm Reset",
		"Clear all play stats?\nThis cannot be undone.",
		"OK",
		"Cancel",
		false,
		confirm_cb,
		cancel_cb
	)

func _on_item_long_pressed(item_node):
	var item_data = item_node.get("item_data")
	if not item_data is StatItem: return
	
	var window = detail_window_scene.instantiate()
	add_child(window)
	
	var viewport_size = get_viewport().get_visible_rect().size
	var min_dim = min(viewport_size.x, viewport_size.y)
	var dynamic_font_size = int(max(14, min_dim * 0.03))
	
	var subs = item_data.sub_carts.duplicate(true)
	if subs.is_empty():
		subs[item_data.filename] = {"seconds": item_data._sort_seconds, "launches": item_data._sort_launches}
		
	var author_val = "Unknown"
	if _cached_metadata and _cached_metadata.has(item_data.base_key):
		author_val = _cached_metadata[item_data.base_key].get("author", "Unknown")
		
	var data = {
		"title": item_data.name,
		"author": author_val,
		"sub_carts": subs,
		"font_size": dynamic_font_size
	}

	# The detail window is usually sized to fill. Ensure it displays over the list.
	window.setup(data)
	
	# Optional: restore focus when closed
	window.tree_exited.connect(func():
		if _last_focused_item and is_instance_valid(_last_focused_item):
			_last_focused_item.grab_focus()
	)
