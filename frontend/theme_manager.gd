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
			print("ThemeManager: Found themed resource: ", theme_path)
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
