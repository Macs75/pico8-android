extends Node
class_name ThemeManager

# Constants
const THEMES_DIR_NAME = "themes"
const THEMES_PATH = "/storage/emulated/0/Documents/pico8/themes" # Hardcoded backup, but we should use PicoBootManager.PUBLIC_FOLDER

static func get_themes_dir() -> String:
	return PicoBootManager.PUBLIC_FOLDER + "/" + THEMES_DIR_NAME

# Returns a list of available theme names (folders and zips combined)
static func get_theme_list() -> Array:
	var themes = []
	var dir = DirAccess.open(get_themes_dir())
	
	if not dir:
		# Try to create it if it doesn't exist
		DirAccess.make_dir_recursive_absolute(get_themes_dir())
		dir = DirAccess.open(get_themes_dir())
		if not dir:
			print("ThemeManager: Could not open or create themes directory.")
			return []

	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	var found_themes = {}
	
	while file_name != "":
		if not file_name.begins_with("."):
			if dir.current_is_dir():
				found_themes[file_name] = true
			elif file_name.ends_with(".zip"):
				var theme_name = file_name.get_basename()
				if not found_themes.has(theme_name):
					found_themes[theme_name] = true
		
		file_name = dir.get_next()
	
	themes = found_themes.keys()
	themes.sort()
	
	# Always include "Default" (empty string or generic name)
	# We'll handle "Default" at the UI level or return it here? 
	# Let's return just the found ones, UI adds "Default" at index 0
	
	return themes

static func get_current_theme() -> String:
	return PicoBootManager.get_setting("settings", "current_theme", "")

static func set_theme(theme_name: String):
	if theme_name == "Default":
		theme_name = ""
		
	PicoBootManager.set_setting("settings", "current_theme", theme_name)
	
	if not theme_name.is_empty():
		_extract_theme_if_needed(theme_name)

# Returns the full path to a resource for the current theme, or fallback
# fallback_path is usually PicoBootManager.PUBLIC_FOLDER + "/" + filename
static func get_resource_path(filename: String) -> String:
	var current_theme = get_current_theme()
	
	# 1. Check Theme Folder
	if not current_theme.is_empty():
		var theme_path = get_themes_dir() + "/" + current_theme + "/" + filename
		if FileAccess.file_exists(theme_path):
			# print("ThemeManager: Found themed resource: ", theme_path)
			return theme_path
			
	# 2. Key functionality: Check PUBLIC_FOLDER (legacy/default location)
	var default_path = PicoBootManager.PUBLIC_FOLDER + "/" + filename
	if FileAccess.file_exists(default_path):
		return default_path
		
	return ""

static func _extract_theme_if_needed(theme_name: String):
	var theme_dir = get_themes_dir() + "/" + theme_name
	
	# If folder exists, we assume it's ready (per requirements "keep only one" logic)
	if DirAccess.dir_exists_absolute(theme_dir):
		return
		
	# Check for zip
	var zip_path = get_themes_dir() + "/" + theme_name + ".zip"
	if FileAccess.file_exists(zip_path):
		print("ThemeManager: Extracting theme zip: ", zip_path)
		
		# Create destination directory
		var err = DirAccess.make_dir_recursive_absolute(theme_dir)
		if err != OK:
			print("ThemeManager: Failed to create theme dir: ", error_string(err))
			return
			
		var reader = ZIPReader.new()
		err = reader.open(zip_path)
		if err != OK:
			print("ThemeManager: Failed to open zip: ", error_string(err))
			return
			
		var files = reader.get_files()
		for file in files:
			# Skip directories in the file list (entries ending with /)
			if file.ends_with("/"):
				continue
				
			var buffer = reader.read_file(file)
			if buffer:
				# Use base file name to flatten structure if needed? 
				# Requirement: "uncompress the content in a folder with the same name"
				# We should probably respect internal structure BUT simple themes are likely flat.
				# Let's just write to the theme dir.
				var target_path = theme_dir + "/" + file
				
				# Ensure subdirectories exist if zip has folders
				var base_dir = target_path.get_base_dir()
				if not DirAccess.dir_exists_absolute(base_dir):
					DirAccess.make_dir_recursive_absolute(base_dir)
				
				var f = FileAccess.open(target_path, FileAccess.WRITE)
				if f:
					f.store_buffer(buffer)
					f.close()
				else:
					print("ThemeManager: Failed to write file: ", target_path)
					
		reader.close()
		print("ThemeManager: Extraction complete.")

static var _cached_layout: Dictionary = {}
static var _cached_layout_theme: String = ""
static var _cached_layout_orientation: bool = false # false=portrait, true=landscape

static func get_theme_layout(is_landscape: bool) -> Dictionary:
	var current_theme = get_current_theme()
	if current_theme.is_empty():
		return {}
		
	# Check Cache
	if _cached_layout_theme == current_theme and _cached_layout_orientation == is_landscape:
		return _cached_layout

	var layout_file = "layout_landscape.json" if is_landscape else "layout_portrait.json"
	var path = get_themes_dir() + "/" + current_theme + "/" + layout_file
	
	if FileAccess.file_exists(path):
		var content = FileAccess.get_file_as_string(path)
		var json = JSON.new()
		var err = json.parse(content)
		if err == OK:
			_cached_layout = json.data
			_cached_layout_theme = current_theme
			_cached_layout_orientation = is_landscape
			print("ThemeManager: Loaded layout from ", path)
			return _cached_layout
		else:
			print("ThemeManager: Failed to parse layout JSON: ", json.get_error_message())
	
	# Clear cache if not found or invalid
	_cached_layout = {}
	_cached_layout_theme = current_theme
	_cached_layout_orientation = is_landscape
	return {}

static func validate_theme(theme_name: String) -> Dictionary:
	var theme_dir = get_themes_dir() + "/" + theme_name
	var zip_path = get_themes_dir() + "/" + theme_name + ".zip"
	var is_zip = not DirAccess.dir_exists_absolute(theme_dir) and FileAccess.file_exists(zip_path)
	
	var reader: ZIPReader = null
	if is_zip:
		reader = ZIPReader.new()
		var err = reader.open(zip_path)
		if err != OK:
			return {"is_valid": false, "error": "Could not open ZIP: " + error_string(err)}
			
	var results = []
	
	# Check Landscape
	var err_l = _validate_orientation(theme_name, true, is_zip, reader)
	if not err_l.is_empty():
		results.append(err_l)
		
	# Check Portrait
	var err_p = _validate_orientation(theme_name, false, is_zip, reader)
	if not err_p.is_empty():
		results.append(err_p)
		
	if reader:
		reader.close()
		
	if results.is_empty():
		return {"is_valid": true, "error": ""}
	else:
		return {"is_valid": false, "error": "\n".join(results)}

static func _validate_orientation(theme_name: String, is_landscape: bool, is_zip: bool, reader: ZIPReader) -> String:
	var layout_file = "layout_landscape.json" if is_landscape else "layout_portrait.json"
	var bezel_files = []
	if is_landscape:
		bezel_files = ["bezel_landscape.png", "bezel.png"]
	else:
		bezel_files = ["bezel_portrait.png", "bezel.png"]
		
	var layout_data = _get_layout_data(theme_name, layout_file, is_zip, reader)
	if layout_data.is_empty():
		return "" # No layout file for this orientation, skipping validation
		
	if not layout_data.has("bezel_size"):
		return "" # No bezel_size specified in layout, skipping validation
		
	var expected_size = Vector2(layout_data["bezel_size"][0], layout_data["bezel_size"][1])
	
	# Find first available bezel file
	var actual_size = Vector2.ZERO
	var found_bezel = ""
	for bf in bezel_files:
		actual_size = _get_bezel_size(theme_name, bf, is_zip, reader)
		if actual_size != Vector2.ZERO:
			found_bezel = bf
			break
			
	if found_bezel.is_empty():
		# This might be an error or just a theme without a bezel but with a layout
		# If it has bezel_size, it probably EXPECTS a bezel.
		return ""

	if actual_size != expected_size:
		var orient_str = "Landscape" if is_landscape else "Portrait"
		return "Theme '%s' (%s): Bezel size mismatch.\nSpecified: %dx%d, Actual: %dx%d (%s)" % [
			theme_name, orient_str, int(expected_size.x), int(expected_size.y),
			int(actual_size.x), int(actual_size.y), found_bezel
		]
		
	return ""

static func _get_layout_data(theme_name: String, filename: String, is_zip: bool, reader: ZIPReader) -> Dictionary:
	var content = ""
	if is_zip:
		if reader.get_files().has(filename):
			var buffer = reader.read_file(filename)
			if buffer:
				content = buffer.get_string_from_utf8()
	else:
		var path = get_themes_dir() + "/" + theme_name + "/" + filename
		if FileAccess.file_exists(path):
			content = FileAccess.get_file_as_string(path)
			
	if not content.is_empty():
		var json = JSON.new()
		if json.parse(content) == OK:
			if json.data is Dictionary:
				return json.data
	return {}

static func _get_bezel_size(theme_name: String, filename: String, is_zip: bool, reader: ZIPReader) -> Vector2:
	var image = Image.new()
	var err = ERR_FILE_NOT_FOUND
	
	if is_zip:
		if reader.get_files().has(filename):
			var buffer = reader.read_file(filename)
			if buffer:
				err = image.load_png_from_buffer(buffer)
	else:
		var path = get_themes_dir() + "/" + theme_name + "/" + filename
		if FileAccess.file_exists(path):
			err = image.load(path)
			
	if err == OK:
		return Vector2(image.get_width(), image.get_height())
	return Vector2.ZERO
