extends "res://list_editor_base.gd"
class_name FavouritesEditor

var item_scene = preload("res://favourites_item.tscn")
const FavouritesManagerScript = preload("res://favourites_manager.gd")

@onready var btn_save = %BtnSave
@onready var btn_shortcut = %BtnShortcut
@onready var btn_reset = %BtnReset

func _ready():
	super._ready() # Calls base class _ready which sets up UI and networking
	
	btn_save.pressed.connect(_on_save)
	btn_shortcut.pressed.connect(_on_shortcut_pressed)
	
	btn_save.gui_input.connect(_on_explicit_gui_input.bind(btn_save))
	btn_shortcut.gui_input.connect(_on_explicit_gui_input.bind(btn_shortcut))

func _setup_sort_options():
	option_sort.clear()
	option_sort.add_item("Manual", 0)
	option_sort.add_item("Name", 1)
	option_sort.add_item("Author", 2)
	option_sort.add_item("Launches", 3)
	option_sort.add_item("Play Time", 4)

func _load_items_from_source() -> Array:
	var items = FavouritesManagerScript.load_favourites()
	
	for item in items:
		var stat_cart_id = item.cart_id if not item.cart_id.is_empty() else ""
		var stat_filename = item.filename if not item.filename.is_empty() else ""
		var stat_base = item.key if not item.key.is_empty() else ""
		
		var stats = ActivityLogAnalyzer.get_cart_stats(stat_cart_id, stat_filename, stat_base)
		item._sort_launches = stats.launches
		item._sort_seconds = stats.seconds
			
	return items

func _apply_sort():
	var get_sort_val = func(item, property: String):
		match property:
			"Name": return str(item.name).to_lower()
			"Author": return str(item.author).to_lower()
			"Launches": return int(item._sort_launches)
			"Play Time": return int(item._sort_seconds)
		return ""

	var asc = is_ascending

	match option_sort.get_item_text(option_sort.selected):
		"Manual":
			_all_items = _manual_order_cache.duplicate()
			if not is_ascending:
				_all_items.reverse()
			return
		"Name":
			_all_items.sort_custom(func(a, b):
				var sort_val_a = get_sort_val.call(a, "Name")
				var sort_val_b = get_sort_val.call(b, "Name")
				if sort_val_a == sort_val_b:
					var a_a = get_sort_val.call(a, "Author")
					var a_b = get_sort_val.call(b, "Author")
					if asc:
						return a_a < a_b
					else:
						return a_a > a_b
				if asc:
					return sort_val_a < sort_val_b
				else:
					return sort_val_a > sort_val_b
			)
		"Author":
			_all_items.sort_custom(func(a, b):
				var sort_val_a = get_sort_val.call(a, "Author")
				var sort_val_b = get_sort_val.call(b, "Author")
				if sort_val_a == sort_val_b:
					return get_sort_val.call(a, "Name") < get_sort_val.call(b, "Name")
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
	item_node.drag_enabled = true
	
	# Connect favorites specific signals
	if not item_node.item_dropped.is_connected(_on_item_dropped_reorder):
		item_node.item_dropped.connect(_on_item_dropped_reorder)
	if not item_node.item_reorder_requested.is_connected(_on_item_reorder_requested):
		item_node.item_reorder_requested.connect(_on_item_reorder_requested)
		
	return item_node

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
	btn_save.add_theme_font_size_override("font_size", _size)
	btn_shortcut.add_theme_font_size_override("font_size", _size)

func _apply_subclass_static_focus():
	option_sort.focus_neighbor_left = btn_save.get_path()
	btn_close.focus_neighbor_bottom = btn_save.get_path()
	btn_close.focus_neighbor_right = btn_save.get_path()
	btn_save.focus_neighbor_left = btn_close.get_path()
	btn_save.focus_neighbor_right = btn_shortcut.get_path()
	btn_save.focus_neighbor_top = btn_close.get_path()
	btn_shortcut.focus_neighbor_left = btn_save.get_path()
	btn_shortcut.focus_neighbor_right = option_sort.get_path()
	btn_shortcut.focus_neighbor_top = btn_close.get_path()

func _apply_empty_list_boundary_focus():
	option_sort.focus_neighbor_bottom = btn_close.get_path()
	btn_asc_desc.focus_neighbor_bottom = btn_close.get_path()
	btn_asc_desc.focus_neighbor_right = btn_close.get_path()
	btn_close.focus_neighbor_top = option_sort.get_path()
	btn_close.focus_neighbor_left = btn_asc_desc.get_path()

func _apply_subclass_boundary_focus(last_item: Control):
	btn_close.focus_neighbor_top = last_item.get_path()
	btn_close.focus_neighbor_left = last_item.get_path()

func _on_item_dropped_reorder(_source_idx: int, _target_idx: int):
	_sync_data_from_visual_order()
	option_sort.selected = 0
	is_dragging_item = false

func _on_item_reorder_requested(source_item, target_item):
	var source_idx = source_item.get_index()
	var target_idx = target_item.get_index()
	if source_idx == target_idx: return
	
	list_container.move_child(source_item, target_idx)
	_update_list_indices()
	_sync_data_from_visual_order()
	option_sort.selected = 0
	_update_surgical_focus_range(source_idx, target_idx)

func _on_save():
	var save_data: Array[FavouritesManager.FavouriteItem] = []
	for item in _all_items:
		if item is FavouritesManager.FavouriteItem:
			save_data.append(item)
	
	var success = FavouritesManagerScript.save_favourites(save_data)
	if success:
		_is_dirty = true
		var orig = btn_save.text
		btn_save.text = "Saved!"
		await get_tree().create_timer(1.0).timeout
		if is_instance_valid(btn_save):
			btn_save.text = orig
	else:
		btn_save.text = "Error!"

func _on_shortcut_pressed():
	if Applinks and _last_focused_item and is_instance_valid(_last_focused_item):
		var item_data = _last_focused_item.get("item_data")
		if item_data:
			var ident = item_data.get("filename", "") if item_data is Dictionary else (item_data.filename if "filename" in item_data else "")
			if ident.is_empty():
				ident = item_data.get("cart_id", "") if item_data is Dictionary else (item_data.cart_id if "cart_id" in item_data else "")
			if not ident.is_empty():
				var shortcut_name = item_data.get("name", ident) if item_data is Dictionary else (item_data.name if "name" in item_data else ident)
				var cart_path = _get_background_image_path(item_data)
				Applinks.create_shortcut(shortcut_name, cart_path)
				var orig = btn_shortcut.text
				btn_shortcut.text = "Created!"
				await get_tree().create_timer(1.0).timeout
				if is_instance_valid(btn_shortcut):
					btn_shortcut.text = orig
