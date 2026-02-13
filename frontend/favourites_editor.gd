extends CanvasLayer

enum EditorMode {FAVORITES, STATS}
var current_mode: EditorMode = EditorMode.FAVORITES

var item_scene = preload("res://favourites_item.tscn")
const FavouritesManagerScript = preload("res://favourites_manager.gd")
const ActivityLogAnalyzerScript = preload("res://activity_log_analyzer.gd")
var current_items: Array[FavouritesManagerScript.FavouriteItem] = []
var _all_items: Array[FavouritesManagerScript.FavouriteItem] = [] # Full list before pagination
var _items_per_page: int = 25
var _loaded_count: int = 0
var is_ascending: bool = true
var current_font_size: int = 0
var _cached_metadata: Dictionary = {}
var _last_focused_item: Control = null

func _ready():
	_configure_ui_for_mode()
	
	%BtnClose.pressed.connect(_on_close)
	# Only connect Save if in Favorites mode
	if current_mode == EditorMode.FAVORITES:
		%BtnSave.pressed.connect(_on_save)
		%BtnShortcut.pressed.connect(_on_shortcut_pressed)
	
	%OptionSort.item_selected.connect(_on_sort_criteria_changed)
	%OptionSort.gui_input.connect(_on_explicit_gui_input.bind(%OptionSort))
	
	# configure sort options
	_setup_sort_options()
	
	%BtnAscDesc.pressed.connect(_on_asc_desc_toggled)
	%BtnAscDesc.gui_input.connect(_on_explicit_gui_input.bind(%BtnAscDesc))
	
	# Footer Connections (Controller Support)
	%BtnClose.gui_input.connect(_on_explicit_gui_input.bind(%BtnClose))
	if current_mode == EditorMode.FAVORITES:
		%BtnSave.gui_input.connect(_on_explicit_gui_input.bind(%BtnSave))
		%BtnShortcut.gui_input.connect(_on_explicit_gui_input.bind(%BtnShortcut))
	
	# Initial layout
	_update_layout()
	
	_load_data()
	
	# Connect to resize after initial load
	get_tree().root.size_changed.connect(_update_layout)
	
	# Disable game input
	if PicoVideoStreamer.instance:
		print("FavouritesEditor: Disabling PICO-8 Input (Instance found)")
		# Use internal blocked flag for safer blocking
		if PicoVideoStreamer.instance.has_method("set_input_blocked"):
			PicoVideoStreamer.instance.set_input_blocked(true)

		PicoVideoStreamer.instance.set_process_unhandled_input(false)
		PicoVideoStreamer.instance.set_process_input(false)
	else:
		print("FavouritesEditor: ERROR - PicoVideoStreamer.instance is NULL! Cannot disable input.")

		
	# Enable processing for Controller Polling (Popup) and Auto-Scroll (Restricted)
	set_process(true)

func _exit_tree():
	# Re-enable game input with a delay to prevent the closing event (B button release) 
	# from leaking into PICO-8. We use a timer connected to a lambda to ensure it runs
	# even after this node is freed.
	var tree = get_tree()
	if tree:
		var tmr = tree.create_timer(0.2)
		tmr.timeout.connect(func():
			# Check if a new FavouritesEditor has been opened in the meantime
			if tree.root.has_node("FavouritesEditor"):
				print("FavouritesEditor: New instance detected, keeping input disabled.")
				return
				
			var streamer = PicoVideoStreamer.instance
			if is_instance_valid(streamer):
				print("FavouritesEditor: Enabling PICO-8 Input (Timer expired)")
				if streamer.has_method("set_input_blocked"):
					streamer.set_input_blocked(false)
				
				streamer.set_process_unhandled_input(true)
				streamer.set_process_input(true)
		)

func _update_layout():
	var viewport_size = get_viewport().get_visible_rect().size
	var min_dim = min(viewport_size.x, viewport_size.y)
	
	var dynamic_font_size = int(max(12, min_dim * 0.03))
	current_font_size = dynamic_font_size
	
	# Ensure scroll follows focus -> DISABLE to allow manual smooth scroll
	%ListContainer.get_parent().follow_focus = false
	
	# Apply dynamic margins
	var v_margin = int(viewport_size.y * 0.08)
	var h_margin = int(viewport_size.x * 0.06)
	
	var margin_container = $Panel/MarginContainer
	margin_container.add_theme_constant_override("margin_top", v_margin)
	margin_container.add_theme_constant_override("margin_bottom", v_margin)
	margin_container.add_theme_constant_override("margin_left", h_margin)
	margin_container.add_theme_constant_override("margin_right", h_margin)
	
	# Dynamic Spacing for Font
	# We update the existing Local FontVariation (FontVariation_bqpnx) attached to the title label
	# This resource is shared by all nodes in the scene that use it, so updating it here updates them all!
	var spacing_val = int(dynamic_font_size * -0.25)
	
	var title_font = $Panel/MarginContainer/VBox/Header/LabelTitle.get_theme_font("font")
	if title_font is FontVariation:
		title_font.spacing_space = spacing_val
	
	# Apply to Header logic (sizes)
	$Panel/MarginContainer/VBox/Header/LabelTitle.add_theme_font_size_override("font_size", int(dynamic_font_size * 1.1))
	$Panel/MarginContainer/VBox/Header/SortButtons/LabelSort.add_theme_font_size_override("font_size", int(dynamic_font_size * 0.9))
	%OptionSort.add_theme_font_size_override("font_size", int(dynamic_font_size * 0.9))
	%OptionSort.get_popup().add_theme_font_size_override("font_size", int(dynamic_font_size * 0.9))
	%BtnAscDesc.add_theme_font_size_override("font_size", dynamic_font_size)
	
	# Apply to Footer sizes
	%BtnClose.add_theme_font_size_override("font_size", dynamic_font_size)
	%BtnSave.add_theme_font_size_override("font_size", dynamic_font_size)
	%BtnReset.add_theme_font_size_override("font_size", dynamic_font_size)
	%BtnShortcut.add_theme_font_size_override("font_size", dynamic_font_size)
	
	# Update items (only size needs to be passed down now, as they share the font resource or rely on theme)
	# Wait, items are instantiated scenes (favourites_item.tscn). 
	# They do NOT share the local `FontVariation_bqpnx` from `favourites_editor.tscn` unless we passed it to them.
	# But `favourites_item.tscn` likely uses the default theme or its own setup.
	# If we want items to use this spacing, we MUST pass the modified font to them.
	
	for item in %ListContainer.get_children():
		if item.has_method("set_font_size"):
			item.set_font_size(dynamic_font_size)
		
		# Apply the shared font to items if they are labels who need it
		if title_font is FontVariation:
			if item.has_node("%LabelName"):
				item.get_node("%LabelName").add_theme_font_override("font", title_font)
			if item.has_node("%LabelAuthor"):
				if not (item.item_data is Dictionary and item.item_data.get("is_stat_item", false)):
					item.get_node("%LabelAuthor").add_theme_font_override("font", title_font)
	
	# Update items
	for item in %ListContainer.get_children():
		if item.has_method("set_font_size"):
			item.set_font_size(dynamic_font_size)
		elif item is Button:
			item.add_theme_font_size_override("font_size", dynamic_font_size)
			item.custom_minimum_size.y = dynamic_font_size * 2.0

func _configure_ui_for_mode():
	if current_mode == EditorMode.STATS:
		$Panel/MarginContainer/VBox/Header/LabelTitle.text = "📶 Play Stats"
		%BtnSave.visible = false
		%BtnShortcut.visible = false
		%BtnReset.visible = true
		
		# Connect if not already connected (check connection to avoid dupes if called multiple times, though usually called once)
		if not %BtnReset.pressed.is_connected(_on_reset_pressed):
			%BtnReset.pressed.connect(_on_reset_pressed)
			%BtnReset.gui_input.connect(_on_explicit_gui_input.bind(%BtnReset))
		
	else:
		$Panel/MarginContainer/VBox/Header/LabelTitle.text = "💟 Favorites"
		%BtnSave.visible = true
		%BtnShortcut.visible = true
		%BtnReset.visible = false


func _setup_sort_options():
	%OptionSort.clear()
	if current_mode == EditorMode.FAVORITES:
		%OptionSort.add_item("Manual", 0)
		%OptionSort.add_item("Name", 1)
		%OptionSort.add_item("Author", 2)
		%OptionSort.add_item("Launches", 3)
		%OptionSort.add_item("Play Time", 4)
	else:
		# Stats Mode: No Manual, No Author (unless we repurpose)
		# We'll map IDs to keep logic similar: 1=Name, 3=Launches, 4=Time
		%OptionSort.add_item("Name", 1)
		%OptionSort.add_item("Launches", 3)
		%OptionSort.add_item("Play Time", 4)
		# Default to Play Time
		%OptionSort.selected = 2 # Index 2 is "Play Time" (ID 4)
		
		# set descending by default for stats
		is_ascending = false
		%BtnAscDesc.text = "⬇️"


func _load_data():
	if current_mode == EditorMode.FAVORITES:
		# Load raw items
		_all_items = FavouritesManagerScript.load_favourites()
	else:
		# Load Stats
		_all_items = []
		var data = ActivityLogAnalyzer.cached_data
		
		# Load Metadata Cache from static reference (populated by worker thread)
		_cached_metadata = MetadataCache.cached_metadata
		
		if data.has("carts"):
			for key in data.carts:
				var entry = data.carts[key]
				# Create a pseudo-object similar to FavouriteItem for compatibility
				# Repurposing 'author' field for stats display
				# Key is already the base name (no extension)
				var name_clean = key
				
				# Enrich from Metadata
				if _cached_metadata.has(key):
					var meta = _cached_metadata[key]
					if meta.get("title") != null and not meta.title.is_empty():
						name_clean = meta.title

				var time_fmt = activity_time_fmt(entry.seconds)
				var stats_str = "%s|%3d" % [time_fmt, entry.launches]
				
				# Determine correct filename for image loading and stat lookup
				var is_bbs = key.is_valid_int()
				
				# Handle Dictionary sub_carts (new format) vs Array (old format, though reset is forced)
				# Safety: find first sub-cart filename if available
				var rep_filename = entry.sub_carts.keys()[0]
				var item_cart_id = key if is_bbs else rep_filename.get_basename().get_basename()
				
				_all_items.append({
					"name": name_clean,
					"author": stats_str,
					"cart_id": item_cart_id,
					"filename": rep_filename,
					"is_stat_item": true, # Marker
					"_sort_seconds": entry.seconds,
					"_sort_launches": entry.launches
				})

	# Prepare pagination
	_apply_sort()
	
	current_items = [] # Will be filled by _load_next_page
	_loaded_count = 0
	
	# Clear container before loading first page
	for child in %ListContainer.get_children():
		child.queue_free()
		
	_load_next_page()
	
	# Initial focus on first item if available
	if _all_items.size() > 0:
		call_deferred("_grab_initial_focus")

# Helper for formatting
func activity_time_fmt(total_seconds: int) -> String:
	var h = int(total_seconds / 3600.0)
	var m = int((total_seconds % 3600) / 60.0)
	var s = total_seconds % 60
	if h > 0:
		return "%dh:%02dm" % [h, m]
	return "%02dm:%02ds" % [m, s]

func _grab_initial_focus():
	if %ListContainer.get_child_count() > 0:
		%ListContainer.get_child(0).grab_focus()

func _refresh_list():
	# Clear existing children immediately to ensure get_children() later 
	# only returns the new nodes
	for child in %ListContainer.get_children():
		%ListContainer.remove_child(child)
		child.queue_free()
	
	
	# OPTIMIZATION: Hide container while populating to prevent layout recalculation on each add_child
	%ListContainer.visible = false
	
	# Batch arrays for deferred operations
	var items_to_setup = []
	
	# Populate new list - MINIMAL operations per item
	for i in range(current_items.size()):
		var item_data = current_items[i]
		var item_node = item_scene.instantiate()
		%ListContainer.add_child(item_node)
		
		# Just set data - defer everything else
		item_node.setup(item_data, i)
		items_to_setup.append(item_node)
	
	# Batch signal connections and configuration
	for item_node in items_to_setup:
		var item_data = item_node.item_data
		
		# Connect signals
		if current_mode == EditorMode.FAVORITES:
			if not item_node.item_dropped.is_connected(_on_item_dropped_reorder):
				item_node.item_dropped.connect(_on_item_dropped_reorder)
			
		if not item_node.item_reorder_requested.is_connected(_on_item_reorder_requested):
			item_node.item_reorder_requested.connect(_on_item_reorder_requested)
			
		if item_node.has_signal("request_move_step"):
			item_node.request_move_step.connect(_on_item_request_move_step.bind(item_node))
			
		if not item_node.focus_entered.is_connected(_on_item_focused):
			item_node.focus_entered.connect(_on_item_focused.bind(item_data, item_node))
			
		# Mode Specifics
		if current_mode == EditorMode.STATS:
			# Hide Drag Handle
			if item_node.has_node("Content/DragHandle"):
				item_node.get_node("Content/DragHandle").visible = false
			
			# Disable Drag Logic
			item_node.drag_enabled = false
			
			# Connect Long Press for Details
			if not item_node.item_long_pressed.is_connected(_on_item_long_pressed):
				item_node.item_long_pressed.connect(_on_item_long_pressed)
		else:
			# Favorites Mode: Ensure drag handle is visible and enabled
			if item_node.has_node("Content/DragHandle"):
				item_node.get_node("Content/DragHandle").visible = true
			item_node.drag_enabled = true
	
	# Apply font sizes in batch BEFORE showing
	if current_font_size > 0:
		for item_node in items_to_setup:
			item_node.set_font_size(current_font_size)
	
	# Show container - this triggers a single layout recalculation for all items
	%ListContainer.visible = true
	
	_update_full_focus_chain()

func _load_next_page():
	# Load next batch of items
	var start_idx = _loaded_count
	var end_idx = mini(start_idx + _items_per_page, _all_items.size())
	
	# If this is the first load, use full refresh
	if start_idx == 0:
		for i in range(start_idx, end_idx):
			current_items.append(_all_items[i])
		_loaded_count = end_idx
		_refresh_list()
	else:
		# Incremental load - just add new items without re-rendering existing
		# Remove Load More button first
		for child in %ListContainer.get_children():
			if child is Button:
				%ListContainer.remove_child(child)
				child.queue_free()
				break
		
		# Add only the new items
		for i in range(start_idx, end_idx):
			var item_data = _all_items[i]
			current_items.append(item_data)
			
			# Instantiate and setup new item
			var item_node = item_scene.instantiate()
			%ListContainer.add_child(item_node)
			item_node.setup(item_data, current_items.size() - 1)
			
			# Connect signals
			if current_mode == EditorMode.FAVORITES:
				if not item_node.item_dropped.is_connected(_on_item_dropped_reorder):
					item_node.item_dropped.connect(_on_item_dropped_reorder)
			
			if not item_node.item_reorder_requested.is_connected(_on_item_reorder_requested):
				item_node.item_reorder_requested.connect(_on_item_reorder_requested)
			
			if item_node.has_signal("request_move_step"):
				item_node.request_move_step.connect(_on_item_request_move_step.bind(item_node))
			
			if not item_node.focus_entered.is_connected(_on_item_focused):
				item_node.focus_entered.connect(_on_item_focused.bind(item_data, item_node))
			
			# Mode Specifics
			if current_mode == EditorMode.STATS:
				if item_node.has_node("Content/DragHandle"):
					item_node.get_node("Content/DragHandle").visible = false
				item_node.drag_enabled = false
				if not item_node.item_long_pressed.is_connected(_on_item_long_pressed):
					item_node.item_long_pressed.connect(_on_item_long_pressed)
			else:
				if item_node.has_node("Content/DragHandle"):
					item_node.get_node("Content/DragHandle").visible = true
				item_node.drag_enabled = true
			
			# Apply font size
			if current_font_size > 0:
				item_node.set_font_size(current_font_size)
		
		_loaded_count = end_idx
		_update_full_focus_chain()
	
	# 1. Trigger automatic background loading if we haven't reached the 100-item limit
	if _loaded_count < 100 and _loaded_count < _all_items.size():
		# Wait a small delay to keep UI responsive between batches
		await get_tree().create_timer(1.0).timeout
		_load_next_page()
	# 2. Add manual "Load More" button if we reached the limit but more items remain
	elif _loaded_count < _all_items.size():
		_add_load_more_button()

func _add_load_more_button():
	var load_more_btn = Button.new()
	load_more_btn.text = "⬇ Load More (%d remaining)" % (_all_items.size() - _loaded_count)
	
	# Use current font size if available
	if current_font_size > 0:
		load_more_btn.add_theme_font_size_override("font_size", current_font_size)
		load_more_btn.custom_minimum_size.y = current_font_size * 2.0
	else:
		load_more_btn.custom_minimum_size.y = 60
	
	load_more_btn.pressed.connect(_on_load_more_pressed)
	%ListContainer.add_child(load_more_btn)

func _on_load_more_pressed():
	# Remove the Load More button
	for child in %ListContainer.get_children():
		if child is Button:
			child.queue_free()
			break
	
	# Load next page
	_load_next_page()

func _on_item_focused(item_data, item_node):
	_last_focused_item = item_node
	
	# Only auto-scroll during active user interaction (drag or navigation)
	# Don't scroll when focus changes from passive mouse hover
	if _should_auto_scroll():
		_ensure_node_visible(item_node, false)
	
	var path = ""
	var base_path = FavouritesManagerScript.PICO8_DATA_PATH
	
	# Priority 1: BBS Carts (Col 1 + .p8.png)
	if not item_data.cart_id.is_empty():
		# to support offline multicarts: default is to use /bbs/carts else if the name is numeric we bind the relative path from pico8 folder
		# this may break in the future if the bbs folder structure changes
		var subfolder = "carts"
		if item_data.cart_id.is_valid_int():
			if item_data.cart_id.length() >= 5:
				subfolder = item_data.cart_id[0]
			else:
				subfolder = "0"
		path = base_path + "/bbs/" + subfolder + "/" + item_data.cart_id + ".p8.png"
	# Priority 2: Local Carts (Col 5, exact filename)
	elif not item_data.filename.is_empty():
		path = base_path + "/carts/" + item_data.filename
	
	if not path.is_empty() and FileAccess.file_exists(path):
		var img = Image.load_from_file(path)
		if img:
			var tex = ImageTexture.create_from_image(img)
			if %BackgroundArt:
				%BackgroundArt.texture = tex
		else:
			if %BackgroundArt: %BackgroundArt.texture = null
	else:
		# Clear if no image found
		if %BackgroundArt: %BackgroundArt.texture = null

func _on_item_request_move_step(direction: int, item_node):
	var source_idx = item_node.list_index
	var target_idx = source_idx + direction
	
	if target_idx < 0 or target_idx >= current_items.size():
		return
		
	# 1. Update Visual Tree FIRST
	%ListContainer.move_child(item_node, target_idx)
	
	# 2. Sync data from the new visual state
	_sync_data_from_visual_order()
	
	# 3. Update sort mode to manual
	if current_mode == EditorMode.FAVORITES:
		%OptionSort.selected = 0
	
	_update_surgical_focus_range(source_idx, target_idx)
	_ensure_node_visible(item_node)

func _update_full_focus_chain():
	_setup_static_focus_connections()
	var count = %ListContainer.get_child_count()
	if count == 0:
		_update_boundary_focus() # Fallback for empty list
		return
		
	for i in range(count):
		_update_focus_for_index(i)

func _setup_static_focus_connections():
	# Internal header/footer connections that don't depend on the list order
	%OptionSort.focus_neighbor_right = %BtnAscDesc.get_path()
	%BtnAscDesc.focus_neighbor_left = %OptionSort.get_path()
	
	if current_mode == EditorMode.STATS:
		%OptionSort.focus_neighbor_left = %BtnClose.get_path()
		%BtnClose.focus_neighbor_right = %BtnReset.get_path()
		# Close -> Reset loop
		%BtnClose.focus_neighbor_bottom = %OptionSort.get_path()
		%BtnReset.focus_neighbor_left = %BtnClose.get_path()
		%BtnReset.focus_neighbor_right = %OptionSort.get_path()
		%BtnReset.focus_neighbor_bottom = %OptionSort.get_path()
	else:
		%OptionSort.focus_neighbor_left = %BtnSave.get_path()
		%BtnClose.focus_neighbor_bottom = %BtnSave.get_path()
		%BtnClose.focus_neighbor_right = %BtnSave.get_path()
		%BtnSave.focus_neighbor_left = %BtnClose.get_path()
		%BtnSave.focus_neighbor_right = %BtnShortcut.get_path()
		%BtnSave.focus_neighbor_top = %BtnClose.get_path()
		%BtnShortcut.focus_neighbor_left = %BtnSave.get_path()
		%BtnShortcut.focus_neighbor_right = %OptionSort.get_path()
		%BtnShortcut.focus_neighbor_top = %BtnClose.get_path()

func _update_surgical_focus_range(idx_a: int, idx_b: int):
	var min_idx = clampi(mini(idx_a, idx_b) - 1, 0, %ListContainer.get_child_count() - 1)
	var max_idx = clampi(maxi(idx_a, idx_b) + 1, 0, %ListContainer.get_child_count() - 1)
	
	for i in range(min_idx, max_idx + 1):
		_update_focus_for_index(i)

func _update_focus_for_index(idx: int):
	var items = %ListContainer.get_children()
	var count = items.size()
	if idx < 0 or idx >= count: return
	
	var item = items[idx]
	var prev = items[idx - 1] if idx > 0 else null
	var next = items[idx + 1] if idx < count - 1 else null
	
	# 1. Update the Item itself
	item.focus_neighbor_top = prev.get_path() if prev else %OptionSort.get_path()
	item.focus_neighbor_bottom = next.get_path() if next else %BtnClose.get_path()
	item.focus_neighbor_left = %BtnAscDesc.get_path()
	item.focus_neighbor_right = %BtnClose.get_path()
	
	# 2. Update Boundaries if this index is at an edge
	if idx == 0:
		%OptionSort.focus_neighbor_bottom = item.get_path()
		%BtnAscDesc.focus_neighbor_right = item.get_path()
		%BtnAscDesc.focus_neighbor_bottom = item.get_path()
	
	if idx == count - 1:
		_update_boundary_focus(item)

func _update_boundary_focus(last_item: Control = null):
	var items = %ListContainer.get_children()
	var count = items.size()
	
	if count == 0:
		# Empty list: Header links directly to Footer
		var footer_target = %BtnReset if %BtnReset.visible else %BtnClose
		%OptionSort.focus_neighbor_bottom = footer_target.get_path()
		%BtnAscDesc.focus_neighbor_bottom = %BtnClose.get_path()
		%BtnAscDesc.focus_neighbor_right = %BtnClose.get_path()
		%BtnClose.focus_neighbor_top = %OptionSort.get_path()
		%BtnClose.focus_neighbor_left = %BtnAscDesc.get_path()
		if %BtnReset.visible: %BtnReset.focus_neighbor_top = %OptionSort.get_path()
		return

	if not last_item:
		last_item = items[count - 1]
		
	# Footer points back to last item
	%BtnClose.focus_neighbor_top = last_item.get_path()
	%BtnClose.focus_neighbor_left = last_item.get_path()
	if %BtnReset.visible:
		%BtnReset.focus_neighbor_top = last_item.get_path()
	
	# Ensure the last item points to Footer
	last_item.focus_neighbor_bottom = %BtnClose.get_path()

func _sync_data_from_visual_order():
	# Reconstruct our data arrays based on the ACTUAL current order of UI nodes
	var new_current_items: Array[FavouritesManagerScript.FavouriteItem] = []
	
	for child in %ListContainer.get_children():
		if child.has_method("setup") and child.item_data:
			new_current_items.append(child.item_data)
	
	# Update visible subset
	current_items = new_current_items
	
	# Update the master list segment that matches current_items
	# current_items always starts from index 0 of _all_items
	for i in range(current_items.size()):
		_all_items[i] = current_items[i]
	
	# Sync indices on nodes
	_update_list_indices()

func _update_list_indices():
	var item_idx = 0
	for i in range(%ListContainer.get_child_count()):
		var child = %ListContainer.get_child(i)
		if child.has_method("setup"):
			child.list_index = item_idx
			item_idx += 1

var _scroll_tween: Tween

func _ensure_node_visible(node: Control, wait_for_layout: bool = true):
	# Wait for VBox to rearrange (next frame) if requested
	if wait_for_layout:
		await get_tree().process_frame
	
	if not is_instance_valid(node): return
	
	node.grab_focus()
	
	var scroll: ScrollContainer = %ListContainer.get_parent()
	var top = node.position.y
	var bottom = top + node.size.y
	var scroll_pos = scroll.scroll_vertical
	var view_height = scroll.size.y
	
	# Add a small margin
	var margin = node.size.y * 0.5
	var target_pos = scroll_pos
	
	if top < scroll_pos:
		target_pos = int(max(0, top - margin))
	elif bottom > scroll_pos + view_height:
		target_pos = int(bottom - view_height + margin)
		
	if target_pos != scroll_pos:
		if _scroll_tween:
			_scroll_tween.kill()
		
		# Smooth scroll
		_scroll_tween = create_tween()
		_scroll_tween.tween_property(scroll, "scroll_vertical", target_pos, 0.2) \
			.set_trans(Tween.TRANS_CUBIC) \
			.set_ease(Tween.EASE_OUT)

func _on_item_dropped_reorder(_source_idx: int, _target_idx: int):
	#print("🟢 DROP HANDLER CALLED - source:", source_idx, " target:", target_idx)
	# source_idx/target_idx are ignored because we sync from the FINAL visual state
	# Perform the robust visual sync
	_sync_data_from_visual_order()
	
	# Switch to Manual sort mode
	if current_mode == EditorMode.FAVORITES:
		%OptionSort.selected = 0
	
	# Reset drag state flag
	is_dragging_item = false

func _on_item_reorder_requested(source_item, target_item):
	var source_idx = source_item.get_index()
	var target_idx = target_item.get_index()
	
	if source_idx == target_idx:
		return
		
	# Move in visual tree - this creates the "live" effect
	%ListContainer.move_child(source_item, target_idx)
	
	# Sync indices immediately
	_update_list_indices()
	
	# NEW: Ensure data is synced during live reorder so it's ready even if drop is "aborted"
	_sync_data_from_visual_order()
	
	# Update the sort mode to manual
	if current_mode == EditorMode.FAVORITES:
		%OptionSort.selected = 0
	
	# Refresh focus chain surgically
	_update_surgical_focus_range(source_idx, target_idx)

var is_dragging_item: bool = false
var was_joy_a_pressed: bool = false
var was_joy_b_pressed: bool = false
var popup_was_visible: bool = false

func _notification(what):
	if what == NOTIFICATION_DRAG_BEGIN:
		#print("🔵 DRAG BEGIN")
		is_dragging_item = true
		# Nudge the scroll to break the ScrollContainer's internal panning capture
		call_deferred("_nudge_scroll_to_break_panning")
	elif what == NOTIFICATION_DRAG_END:
		#print("🔴 DRAG END - Will inject click DEFERRED")
		is_dragging_item = false
		
		# Robust Sync: Ensure data matches visual order even if drop was cancelled/missed
		_sync_data_from_visual_order()
		
		# Defer the synthetic click to allow drop event to complete first
		call_deferred("_inject_click_to_cancel_scroll")

func _inject_click_to_cancel_scroll():
	# Simulate a click to cancel the ScrollContainer's stuck drag state
	# User observed that clicking stops the unwanted scrolling
	var mouse_pos = get_viewport().get_mouse_position()
	
	# Send mouse button press
	var press_event = InputEventMouseButton.new()
	press_event.button_index = MOUSE_BUTTON_LEFT
	press_event.pressed = true
	press_event.position = mouse_pos
	press_event.global_position = mouse_pos
	Input.parse_input_event(press_event)
	
	# Send mouse button release immediately after
	var release_event = InputEventMouseButton.new()
	release_event.button_index = MOUSE_BUTTON_LEFT
	release_event.pressed = false
	release_event.position = mouse_pos
	release_event.global_position = mouse_pos
	Input.parse_input_event(release_event)

func _nudge_scroll_to_break_panning():
	var scroll = %ListContainer.get_parent()
	if scroll is ScrollContainer:
		var current = scroll.scroll_vertical
		# Tiny nudge to break engine internal panning state
		scroll.scroll_vertical = current + 1
		scroll.scroll_vertical = current


func _process(delta):
	# 1. Auto-Scroll Logic (Only when dragging)
	if is_dragging_item:
		var viewport_rect = get_viewport().get_visible_rect()
		var mouse_pos = get_viewport().get_mouse_position()
		var scroll_zone = viewport_rect.size.y * 0.15
		var scroll_speed = 500.0 * delta
		
		var scroll_container = %ListContainer.get_parent()
		
		if mouse_pos.y < scroll_zone:
			scroll_container.scroll_vertical -= int(scroll_speed)
		elif mouse_pos.y > (viewport_rect.size.y - scroll_zone):
			scroll_container.scroll_vertical += int(scroll_speed)

	# 2. Popup Controller Logic (Polling because Popup blocks _input)
	var is_popup_visible = %OptionSort.get_popup().visible
	
	if is_popup_visible:
		var joy_a = false
		var joy_b = false
		
		# Check Joypads (Iterate or just check 0)
		if Input.get_connected_joypads().size() > 0:
			joy_a = Input.is_joy_button_pressed(0, JoyButton.JOY_BUTTON_A)
			joy_b = Input.is_joy_button_pressed(0, JoyButton.JOY_BUTTON_B)
			
		# Open Debounce: If popup just appeared and A is held (used to open it),
		# ignore it until released.
		if not popup_was_visible and joy_a:
			was_joy_a_pressed = true
			
		# Just Pressed A -> Select (Enter)
		if joy_a and not was_joy_a_pressed:
			var ev = InputEventKey.new()
			ev.keycode = KEY_ENTER
			ev.pressed = true
			Input.parse_input_event(ev)
			
			# Release immediately to prevent stuck "ui_accept" action
			var ev_release = InputEventKey.new()
			ev_release.keycode = KEY_ENTER
			ev_release.pressed = false
			Input.parse_input_event(ev_release)
			
		# Just Pressed B -> Cancel (Hide)
		if joy_b and not was_joy_b_pressed:
			%OptionSort.get_popup().hide()
			
		was_joy_a_pressed = joy_a
		was_joy_b_pressed = joy_b
		
	popup_was_visible = is_popup_visible
	
	# 3. Focus Navigation Repeat Logic (When NOT holding A)
	# Check if focus is on a List Item
	var focus_owner = get_viewport().gui_get_focus_owner()
	var focus_item = focus_owner if (focus_owner and focus_owner.has_method("setup")) else null
	
	if focus_item:
		var holding_a = _get_polling_action_held()
		
		if not holding_a: # Only repeat focus if NOT doing reorder
			var input_dir = 0
			if Input.is_action_pressed("ui_up"):
				input_dir = -1
			elif Input.is_action_pressed("ui_down"):
				input_dir = 1
				
			if input_dir != 0:
				if input_dir != _last_nav_dir:
					# New press: Reset timer (Action handled by Godot's default "press")
					_nav_repeat_timer = _nav_repeat_delay
					_last_nav_dir = input_dir
				else:
					# Holding same dir
					_nav_repeat_timer -= delta
					if _nav_repeat_timer <= 0:
						_nav_repeat_timer = _nav_repeat_interval
						_manual_focus_step(focus_item, input_dir)
			else:
				_last_nav_dir = 0
				_nav_repeat_timer = 0
	else:
		_last_nav_dir = 0

var _nav_repeat_timer: float = 0.0
var _nav_repeat_interval: float = 0.1
var _nav_repeat_delay: float = 0.4
var _last_nav_dir: int = 0

func _get_polling_action_held() -> bool:
	if Input.get_connected_joypads().size() > 0:
		return Input.is_joy_button_pressed(0, JoyButton.JOY_BUTTON_A)
	return false

func _should_auto_scroll() -> bool:
	# Auto-scroll should happen when user is actively interacting:
	# 1. Dragging with touch screen or mouse (is_dragging_item is set by drag operations)
	# 2. Navigating with keyboard or controller directional inputs
	if is_dragging_item:
		return true
	
	# Check if any directional input is currently pressed (keyboard or controller)
	return Input.is_action_pressed("ui_up") or Input.is_action_pressed("ui_down") or \
		   Input.is_action_pressed("ui_left") or Input.is_action_pressed("ui_right")

func _manual_focus_step(current_node: Control, direction: int):
	# direction -1 = Up, 1 = Down
	var next_path = NodePath()
	if direction == -1:
		next_path = current_node.focus_neighbor_top
	elif direction == 1:
		next_path = current_node.focus_neighbor_bottom
		
	if not next_path.is_empty():
		var next_node = current_node.get_node_or_null(next_path)
		if next_node:
			next_node.grab_focus()

func _input(event: InputEvent) -> void:
	# Keep input if a popup is open (let the popup handle it via polling/internal)
	if %OptionSort.get_popup().visible:
		return

	# Block input if a Custom Dialog is open
	if has_node("CustomConfirmDialog") or has_node("CustomMessageDialog"):
		return

	if event.is_action_pressed("ui_cancel"):
		_on_close()
		get_viewport().set_input_as_handled()
		return
		
	if event is InputEventJoypadButton:
		if event.pressed and (event.button_index == JoyButton.JOY_BUTTON_B):
			_on_close()
			get_viewport().set_input_as_handled()
			return

	# Smart Focus Regain: If no focus, directional input grabs first visible item
	if not get_viewport().gui_get_focus_owner():
		if _is_directional_input(event):
			_regain_focus()
			get_viewport().set_input_as_handled()

func _is_directional_input(event: InputEvent) -> bool:
	return event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down") or \
		   event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right")

func _regain_focus():
	var scroll_container = %ListContainer.get_parent()
	var scroll_rect = scroll_container.get_global_rect()
	
	# Try to find first visible item in list
	for item in %ListContainer.get_children():
		var item_rect = item.get_global_rect()
		# Check if item is roughly inside the scroll view (simple y-overlap check)
		if item_rect.position.y + item_rect.size.y > scroll_rect.position.y and \
		   item_rect.position.y < scroll_rect.position.y + scroll_rect.size.y:
			item.grab_focus()
			return
			
	# Fallback if no list items visible or empty list
	if %OptionSort.is_visible_in_tree():
		%OptionSort.grab_focus()
	elif %BtnClose.is_visible_in_tree():
		%BtnClose.grab_focus()

func _on_sort_criteria_changed(index: int):
	# index 0 is "Manual" only in Favorites mode. 
	# In Stats mode, index 0 is "Name", so we must allow it.
	var criteria = %OptionSort.get_item_id(index)
	
	# Default to Descending for stat-based sorts 
	# so most played games appear at the top immediately.
	if current_mode == EditorMode.FAVORITES and (criteria == 3 or criteria == 4):
		is_ascending = false
		%BtnAscDesc.text = "⬇️"

	if criteria != 0 or current_mode == EditorMode.STATS:
		_apply_sort()
		_reset_pagination_and_refresh()

func _on_asc_desc_toggled():
	is_ascending = not is_ascending
	%BtnAscDesc.text = "⬇️" if not is_ascending else "⬆️"
	_apply_sort()
	_reset_pagination_and_refresh()

func _reset_pagination_and_refresh():
	# Clear existing items and Load More button
	for child in %ListContainer.get_children():
		child.queue_free()
	
	current_items = []
	_loaded_count = 0
	_load_next_page()

func _apply_sort():
	var idx = %OptionSort.selected
	var criteria = %OptionSort.get_item_id(idx)
	
	if criteria == 0: return
	
	# Determine source array (Both modes now use _all_items for pagination)
	var sort_target = _all_items
	
	sort_target.sort_custom(func(a, b):
		if criteria == 3 or criteria == 4:
			# Stats Sorting - use pre-stored values
			var val_a = 0
			var val_b = 0
			
			if current_mode == EditorMode.STATS:
				# In Stats mode, we pre-stored the values
				val_a = a.get("_sort_launches", 0) if criteria == 3 else a.get("_sort_seconds", 0)
				val_b = b.get("_sort_launches", 0) if criteria == 3 else b.get("_sort_seconds", 0)
			else:
				# Favorites Mode - lookup using base key (Col 2) for robustness
				var stats_a = ActivityLogAnalyzer.get_cart_stats(a.cart_id, a.filename, a.key)
				var stats_b = ActivityLogAnalyzer.get_cart_stats(b.cart_id, b.filename, b.key)
				val_a = stats_a.launches if criteria == 3 else stats_a.seconds
				val_b = stats_b.launches if criteria == 3 else stats_b.seconds
			
			if val_a != val_b:
				if is_ascending:
					return val_a < val_b
				else:
					return val_a > val_b
			
			# Secondary Sort by Name (determinism)
			# FIX: Respect is_ascending for the tie-break so the entire list reverses
			var a_name = a.get("name", "") if a is Dictionary else a.name
			var b_name = b.get("name", "") if b is Dictionary else b.name
			
			if is_ascending:
				return a_name.nocasecmp_to(b_name) < 0
			else:
				return a_name.nocasecmp_to(b_name) > 0
		else:
			# String Sorting
			var a_val = a.get("name") if criteria == 1 else a.get("author")
			if a is not Dictionary:
				a_val = a.name if criteria == 1 else a.author
				
			var b_val = b.get("name") if criteria == 1 else b.author
			if b is not Dictionary:
				b_val = b.name if criteria == 1 else b.author
			
			# Handle nulls
			if a_val == null: a_val = ""
			if b_val == null: b_val = ""
			
			if is_ascending:
				return a_val.nocasecmp_to(b_val) < 0
			else:
				return a_val.nocasecmp_to(b_val) > 0
	)
func _on_save():
	var success = FavouritesManagerScript.save_favourites(_all_items)
	
	if success:
		# Restart PICO-8 to apply changes
		var runcmd = get_tree().current_scene.find_child("runcmd")
		if runcmd and runcmd.has_method("restart_pico8"):
			runcmd.restart_pico8()
		
		queue_free()
	else:
		OS.alert("Failed to save favourites!", "Error")

func _on_close():
	queue_free()

func _on_shortcut_pressed():
	# Use the last focused item instead of current focus owner
	# because clicking the button shifts focus to the button itself.
	var focus_owner = _last_focused_item
	
	if not is_instance_valid(focus_owner) or not focus_owner.has_method("setup"):
		# Fallback: if focus is elsewhere, use the first item? 
		if %ListContainer.get_child_count() > 0:
			focus_owner = %ListContainer.get_child(0)
		else:
			return
		
	var item_data = focus_owner.item_data
	var path = _get_cart_path(item_data)
	if path.is_empty():
		OS.alert("Could not find cart file path!", "Error")
		return
		
	if not FileAccess.file_exists(path):
		OS.alert("Cart file does not exist: " + path, "Error")
		return

	var clean_label = _clean_shortcut_label(item_data.name)
	Applinks.create_shortcut(clean_label, path)

func _clean_shortcut_label(label: String) -> String:
	var words = label.replace("_", " ").split(" ", false)
	var capitalized_words = []
	for word in words:
		capitalized_words.append(word.capitalize())
	return " ".join(capitalized_words)

func _get_cart_path(item_data) -> String:
	var path = ""
	var base_path = FavouritesManagerScript.PICO8_DATA_PATH
	
	if not item_data.cart_id.is_empty():
		var subfolder = "carts"
		if item_data.cart_id.is_valid_int():
			if item_data.cart_id.length() >= 5:
				subfolder = item_data.cart_id[0]
			else:
				subfolder = "0"
		path = base_path + "/bbs/" + subfolder + "/" + item_data.cart_id + ".p8.png"
	elif not item_data.filename.is_empty():
		path = base_path + "/carts/" + item_data.filename
		
	return path

func _on_explicit_gui_input(event: InputEvent, control: Control):
	if _is_action_held(event):
		if control is OptionButton:
			control.show_popup()
			# popup handling is automatic usually
			get_viewport().set_input_as_handled()
		elif control is Button:
			control.pressed.emit()
			get_viewport().set_input_as_handled()

func _is_action_held(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_select"):
		return true
		
	if event is InputEventJoypadButton:
		if event.pressed and (event.button_index == JoyButton.JOY_BUTTON_A or event.button_index == JoyButton.JOY_BUTTON_B):
			return true
			
	return false

func _on_item_long_pressed(item_node):
	if current_mode != EditorMode.STATS:
		return
		
	var item_data = item_node.item_data
	var key = item_data.cart_id
	var filename = item_data.filename
	
	# Lookup Full Stats
	# Use global class name to ensure we access the populated static var
	var raw_stats = ActivityLogAnalyzer.cached_data.carts.get(key, {})
	
	# Fallback: Try Normalized Key (e.g. "bas-9" -> "bas")
	if raw_stats.is_empty():
		var normalized_key = ActivityLogAnalyzer._get_base_cart_name(key)
		raw_stats = ActivityLogAnalyzer.cached_data.carts.get(normalized_key, {})
		
		# Fallback 2: Try filename if ID failed
		if raw_stats.is_empty() and not filename.is_empty():
			var norm_file = ActivityLogAnalyzer._get_base_cart_name(filename)
			raw_stats = ActivityLogAnalyzer.cached_data.carts.get(norm_file, {})
			
			if not raw_stats.is_empty():
				key = norm_file # Update key for metadata lookup
		elif not raw_stats.is_empty():
			key = normalized_key # Update key for metadata lookup

	if not raw_stats.is_empty():
		pass # No debug print needed here
	
	# Lookup Metadata
	var meta = _cached_metadata.get(key, {})
	
	# Build Detail Data - Ensure we have valid strings (Dictionary.get returns null if key exists with null value)
	var title_val = meta.get("title")
	if title_val == null: title_val = item_data.name
	
	var author_val = meta.get("author")
	if author_val == null: author_val = "Unknown"
	
	var detail_data = {
		"title": str(title_val),
		"author": str(author_val),
		"sub_carts": raw_stats.get("sub_carts", {}),
		"font_size": current_font_size
	}
	
	# Open Window
	var win_scene = load("res://stats_detail_window.tscn")
	
	if win_scene:
		var win = win_scene.instantiate()
		add_child(win)
		win.setup(detail_data)
	else:
		print("Alert: ALL load attempts failed for StatsWindow")

func _on_reset_pressed():
	# Clean up any existing dialog
	var existing = get_node_or_null("CustomConfirmDialog")
	if existing: existing.queue_free()

	# Use new UIUtils for consistent styling
	var dialog = UIUtils.create_confirm_dialog(
		self,
		"Reset Play Stats",
		"Confirming this action will reset your current play statistics.\n\nYour data will be recalculated from scratch using the Pico-8 activity_log.txt. Please note that the new totals may differ from your current recorded data",
		"Confirm",
		"Cancel",
		false,
		_on_reset_confirmed_action,
		_close_reset_dialog
	)
	
	dialog.visible = true

func _close_reset_dialog():
	var dialog = get_node_or_null("CustomConfirmDialog")
	if dialog: dialog.queue_free()

func _on_reset_confirmed_action():
	_close_reset_dialog()
	
	# 1. Show Wait Dialog
	var wait_dialog = UIUtils.create_message_dialog(self, "Please Wait", "Resetting statistics...\nThis may take a moment.", "")
	wait_dialog.visible = true
	
	# Allow UI to update
	await get_tree().process_frame
	await get_tree().process_frame
	
	# 2. Perform Action
	_on_reset_confirmed()
	
	# 3. Close Wait Dialog
	if wait_dialog: wait_dialog.queue_free()
	
	# 4. Show Success
	var success_dialog = UIUtils.create_message_dialog(self, "Success", "Play stats have been reset successfully.", "OK")
	success_dialog.visible = true

func _on_reset_confirmed():
	# Run analysis with force_reset = true
	ActivityLogAnalyzerScript.perform_analysis(true)
	
	# Refresh the list
	_load_data()
	_reset_pagination_and_refresh()
