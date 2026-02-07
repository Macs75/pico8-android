class_name MetadataCache
extends RefCounted

const METADATA_FILE = "user://cart_metadata.json"
const PICO8_DATA_PATH_ANDROID = "/sdcard/Documents/pico8/data/bbs/"
const PICO8_DATA_PATH_WIN = "F:/Dev/pico8-android/shim"

static var cached_metadata: Dictionary = {}

static func get_pico8_data_path() -> String:
	if OS.get_name() == "Windows":
		return PICO8_DATA_PATH_WIN
	return PICO8_DATA_PATH_ANDROID

static func run_enrichment_async(activity_data: Dictionary):
	print("MetadataCache: Queueing enrichment task...")
	WorkerThreadPool.add_task(_worker_function.bind(activity_data))

static func _worker_function(activity_data: Dictionary):
	print("MetadataCache: Starting enrichment (WorkerThreadPool)...")
	var metadata = _load_metadata()
	# Update cache immediately
	cached_metadata = metadata
	var base_path = get_pico8_data_path()
	var any_change = false
	
	# 1. Sync Keys from Activity Log
	if activity_data.has("carts"):
		for key in activity_data.carts:
			if not metadata.has(key):
				# New entry
				metadata[key] = {
					"lid": key,
					"mid": null,
					"title": null,
					"author": null,
					"ts": null,
					"catsub": null
				}
				any_change = true
				
	# 2. Enrich Missing Info
	for key in metadata:
		var entry = metadata[key]
		# Check if needs enrichment (mid is null)
		if entry.mid == null:
			var info = _find_local_nfo(base_path, key)
			if not info.is_empty():
				# Merge info
				for field in info:
					# Only update valid fields
					if entry.has(field):
						entry[field] = info[field]
				any_change = true
				print("MetadataCache: Enriched ", key, " -> ", info.get("title", "Unknown"))
				
	if any_change:
		_save_metadata(metadata)
		print("MetadataCache: Saved updated metadata.")
	else:
		print("MetadataCache: No metadata changes.")
	
	# Update cache with final data
	cached_metadata = metadata

static func _find_local_nfo(base_path: String, key: String) -> Dictionary:
	# Logic:
	# 1. Determine subfolder
	var subfolder = ""
	if key.is_valid_int() and key.length() >= 5:
		subfolder = key[0]
	elif key.is_valid_int():
		subfolder = "0"
	else:
		subfolder = "carts"
		
	var dir_path = base_path.path_join(subfolder)
	
	# 2. Determine Filename candidates
	var candidates = [
		key + ".nfo",
		"temp-" + key + ".nfo"
	]
	
	for fname in candidates:
		var full_path = dir_path.path_join(fname)
		if FileAccess.file_exists(full_path):
			return _parse_nfo(full_path)
			
	return {}

static func _parse_nfo(path: String) -> Dictionary:
	var f = FileAccess.open(path, FileAccess.READ)
	if not f: return {}
	
	var text = f.get_as_text()
	var data = {}
	var lines = text.split("\n")
	
	for line in lines:
		var parts = line.split(":", true, 1)
		if parts.size() == 2:
			# NFO format: key:value
			# Values might be numeric? Keeping as strings or simple generic types usually fine.
			var k = parts[0].strip_edges()
			var v = parts[1].strip_edges()
			data[k] = v
			
	return data

static func _load_metadata() -> Dictionary:
	if FileAccess.file_exists(METADATA_FILE):
		var f = FileAccess.open(METADATA_FILE, FileAccess.READ)
		if f:
			var json = JSON.new()
			if json.parse(f.get_as_text()) == OK:
				var res = json.data
				if typeof(res) == TYPE_DICTIONARY:
					return res
	return {}

static func _save_metadata(data: Dictionary):
	var f = FileAccess.open(METADATA_FILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
