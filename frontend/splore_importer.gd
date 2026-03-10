extends ListEditorBase
class_name SploreImporter

@onready var input_username: LineEdit = %InputUsername
@onready var label_user: Label = %LabelUser
@onready var option_type: OptionButton = %OptionType
@onready var btn_search: Button = %BtnSearch
@onready var btn_import_selected: Button = %BtnImportSelected
@onready var btn_copy_to_folder: Button = %BtnCopyToFolder
@onready var btn_clear_selection: Button = %BtnClearSelection
@onready var splore_request: HTTPRequest = $SploreRequest

var item_scene = preload("res://splore_cart_item.tscn")

func _ready():
	_items_per_page = PAGE_SIZE # Load all items in one batch so Load More goes at bottom
	super._ready()
	
	# Connect UI Signals
	btn_search.pressed.connect(_on_search_pressed)
	btn_import_selected.pressed.connect(_on_import_selected_pressed)
	btn_copy_to_folder.pressed.connect(_on_copy_to_folder_pressed)
	btn_clear_selection.pressed.connect(_on_clear_selection_pressed)
	
	btn_search.gui_input.connect(_on_explicit_gui_input.bind(btn_search))
	btn_clear_selection.gui_input.connect(_on_explicit_gui_input.bind(btn_clear_selection))
	btn_import_selected.gui_input.connect(_on_explicit_gui_input.bind(btn_import_selected))
	btn_copy_to_folder.gui_input.connect(_on_explicit_gui_input.bind(btn_copy_to_folder))
	
	# Listen for Enter key on the LineEdit to trigger search
	input_username.text_submitted.connect(func(_text): _on_search_pressed())
	input_username.focus_exited.connect(func():
		_on_username_focus_exited()
	)
	input_username.focus_entered.connect(func():
		# Trigger the click simulation automatically on focus
		_simulate_line_edit_tap(input_username)
	)

	_load_items()

func _on_username_focus_exited():
	DisplayServer.virtual_keyboard_hide()
	if Applinks: Applinks.hide_keyboard()

	# Update placeholder based on search type
	option_type.item_selected.connect(_on_type_selected)
	
	#input_username.gui_input.connect(_on_explicit_gui_input.bind(input_username))


func _grab_initial_focus():
	if input_username:
		_simulate_line_edit_tap(input_username)

func _close_grab_focus():
	if btn_close:
		btn_close.grab_focus()

# ----------------- Virtual Methods -----------------

func _apply_subclass_footer_sizes(dynamic_font_size: int):
	# Footer Scaling
	if btn_close:
		btn_close.add_theme_font_size_override("font_size", dynamic_font_size)
		btn_close.custom_minimum_size.y = dynamic_font_size * 1.5
			
	if btn_import_selected:
		btn_import_selected.add_theme_font_size_override("font_size", dynamic_font_size)
		btn_import_selected.custom_minimum_size.y = dynamic_font_size * 1.5
	
	if btn_copy_to_folder:
		btn_copy_to_folder.add_theme_font_size_override("font_size", dynamic_font_size)
		btn_copy_to_folder.custom_minimum_size.y = dynamic_font_size * 1.5

	if btn_clear_selection:
		btn_clear_selection.add_theme_font_size_override("font_size", dynamic_font_size)
		btn_clear_selection.custom_minimum_size.y = dynamic_font_size * 1.5
		
	# Search Row Scaling
	if label_user:
		label_user.add_theme_font_size_override("font_size", dynamic_font_size)
	if input_username:
		input_username.add_theme_font_size_override("font_size", dynamic_font_size)
		input_username.custom_minimum_size.y = dynamic_font_size * 1.8
		input_username.custom_minimum_size.x = dynamic_font_size * 12.0
	if option_type:
		option_type.add_theme_font_size_override("font_size", dynamic_font_size)
		option_type.get_popup().add_theme_font_size_override("font_size", dynamic_font_size)
		option_type.custom_minimum_size.x = dynamic_font_size * 2.5
	if btn_search:
		btn_search.add_theme_font_size_override("font_size", dynamic_font_size)
		btn_search.custom_minimum_size.x = dynamic_font_size * 2.5


func _get_sort_options() -> Array:
	return []

func _on_item_action(item_node):
	# Central point for toggling selection (handles both Mouse and Joypad A)
	if item_node and item_node.has_method("_toggle_selected"):
		item_node._toggle_selected()

func _load_items(_force_reload: bool = false):
	if _current_username.is_empty():
		_load_local_bbs_carts()

func _load_items_from_source() -> Array:
	return _all_items

func _instantiate_item(_item_data, _index: int) -> Control:
	var item_node = item_scene.instantiate()
	if item_node.has_signal("item_action"):
		item_node.item_action.connect(_on_item_action)
	return item_node

func _set_item_background(item_data) -> void:
	var thumb = item_data.get("thumbnail", null) if item_data is Dictionary else null
	if thumb is ImageTexture and background_art:
		background_art.texture = thumb
	elif background_art:
		background_art.texture = null

func _apply_subclass_static_focus():
	# Horizontal Search navigation
	input_username.focus_neighbor_left = btn_copy_to_folder.get_path()
	input_username.focus_neighbor_right = option_type.get_path()
	option_type.focus_neighbor_left = input_username.get_path()
	option_type.focus_neighbor_right = btn_search.get_path()
	btn_search.focus_neighbor_left = option_type.get_path()
	
	# Horizontal Footer navigation
	btn_close.focus_neighbor_left = btn_search.get_path()
	btn_close.focus_neighbor_right = btn_clear_selection.get_path()
	btn_clear_selection.focus_neighbor_left = btn_close.get_path()
	btn_clear_selection.focus_neighbor_right = btn_import_selected.get_path()
	btn_import_selected.focus_neighbor_left = btn_clear_selection.get_path()
	btn_import_selected.focus_neighbor_right = btn_copy_to_folder.get_path()
	btn_copy_to_folder.focus_neighbor_left = btn_import_selected.get_path()
	btn_copy_to_folder.focus_neighbor_right = input_username.get_path()
	
	# Upward navigation from Footer
	btn_close.focus_neighbor_top = input_username.get_path()
	btn_clear_selection.focus_neighbor_top = btn_search.get_path()
	btn_import_selected.focus_neighbor_top = btn_search.get_path()
	btn_copy_to_folder.focus_neighbor_top = btn_search.get_path()

func _apply_empty_list_boundary_focus():
	# Downward navigation from Search to Footer when list is empty
	input_username.focus_neighbor_bottom = btn_close.get_path()
	option_type.focus_neighbor_bottom = btn_close.get_path()
	btn_search.focus_neighbor_bottom = btn_close.get_path()

func _apply_subclass_boundary_focus(last_item: Control):
	# Link the bottom of the list to the clear/import buttons
	last_item.focus_neighbor_bottom = btn_close.get_path()
	btn_clear_selection.focus_neighbor_top = last_item.get_path()
	btn_import_selected.focus_neighbor_top = last_item.get_path()
	btn_copy_to_folder.focus_neighbor_top = last_item.get_path()
	btn_close.focus_neighbor_top = last_item.get_path()
	btn_close.focus_neighbor_left = last_item.get_path()

func _update_focus_for_index(idx: int):
	super._update_focus_for_index(idx)
	var items = list_container.get_children()
	if idx >= 0 and idx < items.size():
		var item = items[idx]
		item.focus_neighbor_left = btn_search.get_path()
		
		if idx == 0:
			# Upward from list to Search
			item.focus_neighbor_top = option_type.get_path()
			
			# Downward from Search to list
			input_username.focus_neighbor_bottom = item.get_path()
			option_type.focus_neighbor_bottom = item.get_path()
			btn_search.focus_neighbor_bottom = item.get_path()

# ----------------- Splore Importer Logic -----------------

# State
var _current_username: String = ""
var _current_type: String = ""
var _current_offset: int = 0
const PAGE_SIZE: int = 32
const BBS_BASE_URL = "https://www.lexaloffle.com/bbs/cpost_lister3.php"

func _on_search_pressed():
	var username = input_username.text.strip_edges()
	if username.is_empty():
		return

	var type_id = option_type.get_selected_id()
	var type_str = "like" # ⭐
	if type_id == 1:
		type_str = "fav" # 🤍
	elif type_id == 2:
		type_str = "by" # 👾

	print("Searching Lexaloffle for %s's %s..." % [username, type_str])

	# Close Android keyboard via both Godot and native plugin
	DisplayServer.virtual_keyboard_hide()
	if Applinks:
		Applinks.hide_keyboard()

	# Save state for pagination
	_current_username = username
	_current_type = type_str
	_current_offset = 0

	_all_items = []
	# Once an online search is performed the local list is gone for this dialog session.
	if btn_copy_to_folder:
		btn_copy_to_folder.disabled = true
	_fetch_page(username, type_str, 0)

func _on_type_selected(index: int):
	if index == 2: # 👾
		input_username.placeholder_text = "Author"
		label_user.text = "Author:"
	else:
		input_username.placeholder_text = "Username"
		label_user.text = "User:"

func _fetch_page(username: String, type_str: String, page_offset: int):
	var url = "%s?max=%d&start_index=%d&cat=7&search=%s:%s&version=000207r&cfil=0" % [
		BBS_BASE_URL, PAGE_SIZE, page_offset, type_str, username
	]
	print("Fetching: ", url)

	btn_search.disabled = true
	btn_search.text = "⏳"

	splore_request.request_completed.connect(_on_request_completed, CONNECT_ONE_SHOT)
	var err = splore_request.request(url)
	if err != OK:
		printerr("HTTPRequest failed to send: ", err)
		btn_search.disabled = false
		btn_search.text = "🔍"

var _is_loading_more: bool = false
var _network_load_more_btn: Button = null

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
	btn_search.disabled = false
	btn_search.text = "🔍"

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		printerr("BBS request failed. Result: %d, HTTP: %d" % [result, response_code])
		return

	print("Response received: %d bytes" % body.size())

	var carts = _decode_splore_png(body)
	print("Decoded %d carts" % carts.size())
	for c in carts:
		print("  - %s by %s [post:%s]" % [c.get("title", "?"), c.get("author", "?"), c.get("post_id", "?")])

	if _is_loading_more:
		# Append rows directly without resetting the list
		_append_new_items(carts)
	else:
		# First page: use normal pagination flow
		for cart in carts:
			_all_items.append(cart)
		_current_offset += carts.size()
		_load_data()

	_is_loading_more = false

	# Add network Load More if the server returned a full page
	if carts.size() == PAGE_SIZE:
		_maybe_add_network_load_more()

func _append_new_items(carts: Array):
	# Remove existing network Load More button
	for child in list_container.get_children():
		if child is Button and child.name == "NetworkLoadMoreBtn":
			child.queue_free()
			break
	_network_load_more_btn = null

	var start_idx = _all_items.size()
	for cart in carts:
		_all_items.append(cart)
	_current_offset += carts.size()

	# Instantiate and add only the new rows
	for i in range(start_idx, _all_items.size()):
		var item_data = _all_items[i]
		current_items.append(item_data)
		var item_node = _instantiate_item(item_data, i)
		if item_node:
			list_container.add_child(item_node)
			item_node.setup(item_data, i)
			_connect_item_signals(item_node)
			if current_font_size > 0 and item_node.has_method("set_font_size"):
				item_node.set_font_size(current_font_size)
	_loaded_count = _all_items.size()
	_update_full_focus_chain()

func _maybe_add_network_load_more():
	var btn = Button.new()
	btn.name = "NetworkLoadMoreBtn"
	btn.text = "⬇ Load More"
	if current_font_size > 0:
		btn.add_theme_font_size_override("font_size", current_font_size)
		btn.custom_minimum_size.y = current_font_size * 2.0
	else:
		btn.custom_minimum_size.y = 60
	btn.pressed.connect(_on_network_load_more_pressed)
	btn.gui_input.connect(_on_explicit_gui_input.bind(btn))
	list_container.add_child(btn)
	_network_load_more_btn = btn

func _on_network_load_more_pressed():
	if _network_load_more_btn:
		_network_load_more_btn.disabled = true
		_network_load_more_btn.text = "⏳ Loading..."
	_is_loading_more = true
	_fetch_page(_current_username, _current_type, _current_offset)


func _load_local_bbs_carts():
	print("Loading local BBS carts via busybox...")
	btn_search.disabled = true
	btn_search.text = "⏳"

	_all_items = []
	list_container.get_children().map(func(c): c.queue_free())
	current_items.clear()

	# Start background thread to avoid blocking UI during OS.execute
	WorkerThreadPool.add_task(_worker_load_local_carts.bind())

func _worker_load_local_carts():
	var bbs_path = MetadataCache.get_pico8_data_path()
	
	# Fallback if no busybox (e.g., Windows test environment)
	if OS.get_name() == "Windows":
		call_deferred("_finalize_local_carts_load", [])
		return
		
	# Command: ls -1t /path/to/bbs/*/*.nfo | head -n 100
	# We use the system sh to expand the wildcards correctly.
	var cmd = "ls -1t " + bbs_path + "*/*.nfo | head -n 100"
	print("Executing simple query: ", cmd)
	
	var output = []
	var exit_code = OS.execute("/system/bin/sh", ["-c", cmd], output)
	
	print("Query finished with exit code %d." % exit_code)
	
	if exit_code != 0 or output.is_empty() or output[0].is_empty():
		print("Simple query returned no results.")
		call_deferred("_finalize_local_carts_load", [])
		return
		
	var files = Array(output[0].split("\n"))
	# Filter out empty strings
	files = files.filter(func(f): return not f.strip_edges().is_empty())
	
	# Safety sort in case system ls -t behaves unexpectedly across multiple globs
	#files.sort_custom(func(a, b):
	#	return FileAccess.get_modified_time(a) > FileAccess.get_modified_time(b)
	#)
	
	var unique_basenames = {}
	var selected_paths = []
	
	for file in files:
		file = file.strip_edges()
		if file.is_empty(): continue
		
		# Deduplication logic
		var filename = file.get_file()
		var basename = filename.trim_suffix(".nfo")
		if basename.begins_with("temp-"):
			basename = basename.trim_prefix("temp-")
			
		if not unique_basenames.has(basename):
			unique_basenames[basename] = true
			selected_paths.append(file)
			
			if selected_paths.size() >= 50:
				break
				
	# Back to main thread to populate UI
	call_deferred("_finalize_local_carts_load", selected_paths)

func _finalize_local_carts_load(nfo_paths: Array):
	var carts = []
	for path in nfo_paths:
		var nfo_data = MetadataCache._parse_nfo(path)
		if nfo_data.is_empty(): continue
		
		var cart = {
			"post_id": nfo_data.get("lid", ""),
			"title": nfo_data.get("title", "Unknown"),
			"author": nfo_data.get("author", "Unknown"),
			"basename": nfo_data.get("mid", ""), # Usually mid
			"target_path": path # Save path just in case
		}
		
		# Look for thumbnail: same folder, [lid].p8.png
		if not cart["post_id"].is_empty():
			var dir_path = path.get_base_dir()
			var png_path
			if cart["basename"].is_valid_int() and not cart["post_id"].is_valid_int():
				png_path = dir_path.path_join(cart["basename"] + ".p8.png")
			else:
				png_path = dir_path.path_join(cart["post_id"] + ".p8.png")
			if FileAccess.file_exists(png_path):
				var img = Image.new()
				if img.load(png_path) == OK:
					cart["thumbnail"] = ImageTexture.create_from_image(img)
					
		carts.append(cart)
		
	_all_items = carts
	_current_offset = carts.size()
	
	btn_search.disabled = false
	btn_search.text = "🔍"
	_load_data()


# ---- Steganography Decoder ----
# The Splore PNG is a 1024x(N*136) image:
#   - 8 columns of 128px-wide cart thumbnails
#   - Each row is 136px tall: 128px thumb + 8px metadata strip below
#   - The metadata strip encodes ASCII chars in the green channel (one char per pixel column)
func _decode_splore_png(body: PackedByteArray) -> Array:
	var img = Image.new()
	var err = img.load_png_from_buffer(body)
	if err != OK:
		printerr("Failed to parse PNG response: ", err)
		return []

	print("PNG size: %dx%d" % [img.get_width(), img.get_height()])

	var carts: Array = []
	var num_rows: int = int(img.get_height() / 136.0) # 128 thumb + 8 metadata strip per row

	for row in range(num_rows):
		for col in range(8):
			var thumb_x = col * 128
			var thumb_y = row * 136
			var metadata_y = thumb_y + 128

			# Read all 5 meaningful rows from the 8px metadata strip (green channel)
			var strip_rows: Array[String] = []
			for r in range(5):
				var raw_chars: PackedByteArray = []
				for px in range(128):
					var char_val = img.get_pixel(thumb_x + px, metadata_y + r).g8
					if char_val == 0:
						break
					raw_chars.append(char_val)
				strip_rows.append(raw_chars.get_string_from_utf8().strip_edges())

			if strip_rows[0].is_empty():
				continue # No data = end of results

			var cart = _parse_metadata(strip_rows)

			# Crop the 128x128 thumbnail and store as ImageTexture (keeps it alive)
			var thumb_img = img.get_region(Rect2i(thumb_x, thumb_y, 128, 128))
			cart["thumbnail"] = ImageTexture.create_from_image(thumb_img)

			carts.append(cart)

	return carts

# Strip row layout (green channel):
#   Row 0: "cat_id post_id subcat_id score replies datetime"
#   Row 1: title
#   Row 2: author
#   Row 3: versioned filename (e.g. "duckhunt-0")
#   Row 4: base filename (e.g. "duckhunt")
func _parse_metadata(rows: Array[String]) -> Dictionary:
	var cart = {}
	# Parse row 0: space-separated numeric fields
	var parts = rows[0].split(" ")
	if parts.size() > 0: cart["cat_id"] = parts[0]
	if parts.size() > 1: cart["post_id"] = parts[1]
	if parts.size() > 5: cart["datetime"] = parts[5] + " " + (parts[6] if parts.size() > 6 else "")
	# Rows 1-4: direct string fields
	cart["title"] = rows[1] if rows.size() > 1 else ""
	cart["author"] = rows[2] if rows.size() > 2 else ""
	cart["filename"] = rows[3] if rows.size() > 3 else ""
	cart["basename"] = rows[4] if rows.size() > 4 else ""
	return cart

func _on_copy_to_folder_pressed():
	var target_copy_path = PicoBootManager.get_setting("settings", "target_copy_path", "")
	var current_dir = target_copy_path if not target_copy_path.is_empty() else "/sdcard"
	DisplayServer.file_dialog_show("Select Target Folder", current_dir, "", false, DisplayServer.FILE_DIALOG_MODE_OPEN_DIR, [], _on_target_dir_selected)

func _on_target_dir_selected(status: bool, selected_paths: PackedStringArray, _filter_index: int):
	if status and not selected_paths.is_empty():
		var raw_path = selected_paths[0]
		# Sanitize path using BootManager logic
		var target_copy_path = PicoBootManager.sanitize_uri(raw_path)
		
		# Extra cleanup for redundancy
		if target_copy_path.begins_with("file://"):
			target_copy_path = target_copy_path.replace("file://", "")

		PicoBootManager.set_setting("settings", "target_copy_path", target_copy_path)

		# copy carts to target_copy_path
		var selected: Array = []
		for child in list_container.get_children():
			if child is SploreCartItem and child.is_selected:
				selected.append(child.item_data)
		
		if selected.is_empty():
			UIUtils.create_message_dialog(self , "None Selected",
			"No carts selected",
			"OK", _close_grab_focus)
			return

		var success_count = 0
		var fail_count = 0

		for cart in selected:
			var source_path = ""
			var dest_filename = ""

			# --- Path resolution for LOCAL carts ---
			# Local carts store the .nfo path in "target_path"
			if cart.has("target_path"):
				var nfo_path: String = cart["target_path"]
				var dir_path = nfo_path.get_base_dir()
				var post_id = cart.get("post_id", "")
				var basename = cart.get("basename", "")

				# Mirror the PNG path logic from _finalize_local_carts_load
				var png_path = ""
				if basename.is_valid_int() and not post_id.is_valid_int():
					png_path = dir_path.path_join(basename + ".p8.png")
				else:
					png_path = dir_path.path_join(post_id + ".p8.png")

				if FileAccess.file_exists(png_path):
					source_path = png_path
					dest_filename = png_path.get_file()

			var dest_path = target_copy_path.path_join(dest_filename)
			var err = DirAccess.copy_absolute(source_path, dest_path)
			if err == OK:
				success_count += 1
			else:
				printerr("SploreImporter: copy failed %s -> %s (err %d)" % [source_path, dest_path, err])
				fail_count += 1

		UIUtils.create_message_dialog(self , "Copy Results",
			"Copied: %d\n Failed %d\n" % [success_count, fail_count],
			"OK", _close_grab_focus)

func _on_import_selected_pressed():
	# Collect all selected cart items from the list
	var selected: Array = []
	for child in list_container.get_children():
		if child is SploreCartItem and child.is_selected:
			selected.append(child.item_data)


	if selected.is_empty():
		UIUtils.create_message_dialog(self , "None Selected",
		"No carts selected",
		"OK", _close_grab_focus)
		return

	# Load existing favourites so we can append without duplicates
	var existing = FavouritesManager.load_favourites()
	var existing_ids: Dictionary = {}
	for fav in existing:
		existing_ids[fav.cart_id] = true

	# Build new lines for selected carts not already in favourites
	var new_lines: Array[String] = []
	var already_in_list: int = 0
	for cart in selected:
		var post_id = cart.get("post_id", "")
		if post_id.is_empty() or existing_ids.has(post_id):
			already_in_list += 1
			continue # Skip duplicates
		# Format: |cart_id|key|pid|author|filename|name
		# cart_id = post_id, key = basename, pid = "", author, filename (versioned), name = title
		var line = "|%s|%s||%s|%s|%s" % [
			post_id,
			cart.get("basename", ""),
			cart.get("author", ""),
			cart.get("filename", ""),
			cart.get("title", "")
		]
		new_lines.append(line)

	if new_lines.is_empty():
		UIUtils.create_message_dialog(self , "No Action",
		"✓ Already in list",
		"OK", _close_grab_focus)
		return

	# Append new lines to the file
	var path = FavouritesManager.get_favourites_file_path()
	# Backup before writing — abort if it fails
	if FileAccess.file_exists(path):
		var err = DirAccess.copy_absolute(path, path + ".bak")
		if err != OK:
			UIUtils.create_message_dialog(self , "Backup Failed",
				"❌ Could not create backup of favourites.txt (error %d).\nImport aborted." % err,
				"OK", _close_grab_focus)
			return

	# Read existing content
	var existing_content = ""
	if FileAccess.file_exists(path):
		var read_file = FileAccess.open(path, FileAccess.READ)
		if read_file:
			existing_content = read_file.get_as_text()
			read_file = null

	# Write new entries first, then old content (new carts go to top like PICO-8 does)
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		printerr("Failed to open favourites file for writing: ", FileAccess.get_open_error())
		UIUtils.create_message_dialog(self , "Failed",
			"❌ Could not open favourites.txt for writing.",
			"OK", _close_grab_focus)
		return

	for line in new_lines:
		file.store_line(line)
	if not existing_content.is_empty():
		file.store_string(existing_content)
	file = null # Close

	_is_dirty = true # Triggers restart_pico8() on close, like the Favourites editor
	print("Imported %d carts to favourites" % new_lines.size())
	UIUtils.create_message_dialog(self , "Imported carts",
	"✓ Imported %d!\n Already in list: %d" % [new_lines.size(), already_in_list],
	"OK", _close_grab_focus)

func _on_clear_selection_pressed():
	for child in list_container.get_children():
		if child is SploreCartItem and child.is_selected:
			child._toggle_selected()

func _on_item_request_move_step(direction: int, item_node):
	pass
