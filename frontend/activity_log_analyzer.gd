class_name ActivityLogAnalyzer
extends RefCounted

const LOG_PATH_ANDROID = "/sdcard/Documents/pico8/data/activity_log.txt"
# Assuming Windows path for testing/fallback based on your environment
const LOG_PATH_WIN = "activity_log.txt"
const STATS_FILE = "user://activity_stats.json"
const UNIT_SECONDS = 3

static var cached_data: Dictionary = {}
static var file_lookup: Dictionary = {}

# Static entry point for the Application
static func perform_analysis(force_reset: bool = false):
	var analyzer = ActivityLogAnalyzer.new()
	analyzer._run(force_reset)

static func get_cart_stats(cart_id: String, filename: String, base_key: String = "") -> Dictionary:
	# Default stats
	var stats = {"launches": 0, "seconds": 0}
	
	if cached_data.is_empty() or not cached_data.has("carts"):
		return stats
		
	# 1. Highest Priority: The base_key provided (usually from Favourites Col 2)
	var key = ""
	if not base_key.is_empty() and cached_data.carts.has(base_key):
		key = base_key
	
	# 2. Try Exact Match via Lookup Map (Sub-Cart -> Base Key)
	if key == "":
		if not filename.is_empty():
			var f = filename.get_file()
			if file_lookup.has(f):
				key = file_lookup[f]
				
	# 3. Try ID (fallback if ID is actually a filename)
	if key == "" and not cart_id.is_empty():
		var f_id = (cart_id + ".p8.png").get_file()
		if file_lookup.has(f_id):
			key = file_lookup[f_id]
			
	# 4. Direct Key Check (if input is already the base key)
	if key == "":
		if cached_data.carts.has(filename):
			key = filename
		elif cached_data.carts.has(cart_id):
			key = cart_id

	if key != "" and cached_data.carts.has(key):
		var entry = cached_data.carts[key]
		stats.launches = entry.launches
		stats.seconds = entry.seconds
		
	return stats

func _run(force_reset: bool = false):
	print("ActivityLogAnalyzer: Starting analysis...")
	
	# DEBUG: Set to true to force re-analysis from scratch (ignoring saved state)
	var debug_reset = force_reset
	var data: Dictionary
	
	if debug_reset:
		print("ActivityLogAnalyzer: FORCE RESET is ON. Ignoring saved stats.")
		data = {"last_analyzed_time": 0, "carts": {}}
	else:
		data = _load_stats()
	
	# Cache it immediately for access
	ActivityLogAnalyzer.cached_data = data
	ActivityLogAnalyzer._rebuild_lookup(data)
	
	var path = LOG_PATH_WIN if OS.get_name() == "Windows" else LOG_PATH_ANDROID
	
	if not FileAccess.file_exists(path):
		if OS.get_name() != "Android":
			print("ActivityLogAnalyzer: Log file not found at: ", path)
			return

	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		print("ActivityLogAnalyzer: Failed to open log file.")
		return

	var current_cart_key = ""
	var current_sub_filename = ""
	var is_in_play_session = false
	var last_line_time = 0

	while not file.eof_reached():
		var line = file.get_line()
		if line.strip_edges().is_empty():
			continue

		# Check if line is a Header (Timestamp + Filename)
		# Format: YYYY-MM-DD HH:MM:SS /path/to/cart.p8...
		if line.length() > 19 and line[4] == "-" and line[13] == ":":
			# It's a header
			# Parse Timestamp
			var time_str = line.substr(0, 19)
			var dict = Time.get_datetime_dict_from_datetime_string(time_str, false)
			var unix_time = Time.get_unix_time_from_datetime_dict(dict)
			
			last_line_time = unix_time
			
			# Optimization: Skip if we already analyzed this deep (UNLESS DEBUG_RESET is true or we are rebuilding)
			# Only process if unix_time >= data.last_analyzed_time
			
			# Extract Cart Name
			var parts = line.split(" ", false, 2)
			# parts[0]=Date, parts[1]=Time, parts[2]=Path
			if parts.size() >= 3:
				var full_path = parts[2].strip_edges()
				var filename = full_path.get_file()
				
				if filename == "untitled.p8":
					current_cart_key = ""
					current_sub_filename = ""
					is_in_play_session = false
				else:
					# Use Base Name Key (grouping split carts)
					current_cart_key = _get_base_cart_name(filename)
					current_sub_filename = filename # Track for session
					
					# Only count launch if we are processing new data
					if unix_time > data.last_analyzed_time:
						if not data.carts.has(current_cart_key):
							data.carts[current_cart_key] = {"launches": 0, "seconds": 0, "sub_carts": {}}
						
						var entry = data.carts[current_cart_key]
						
						# Ensure sub_cart entry exists (handle migration/fixes)
						if not entry.has("sub_carts") or typeof(entry.sub_carts) != TYPE_DICTIONARY:
							entry.sub_carts = {}
						
						if not entry.sub_carts.has(filename):
							entry.sub_carts[filename] = {"launches": 0, "seconds": 0}
						
						# Aggregate Increment
						entry.launches += 1
						# Sub-cart Increment
						entry.sub_carts[filename].launches += 1
						
					# Reset play session state for new cart load
					is_in_play_session = false
			else:
				current_cart_key = ""
				is_in_play_session = false
				
		else:
			# It's a data line (p..._...m...)
			if current_cart_key == "":
				continue
				
			# Only process duration if this block belongs to a timestamp > last_analyzed
			if last_line_time <= data.last_analyzed_time:
				continue
				
			# Count characters
			# Optimization: analyze block instead of char-by-char if possible, but state matters
			for i in range(line.length()):
				var c = line[i]
				
				if c == "p":
					is_in_play_session = true
					data.carts[current_cart_key].seconds += UNIT_SECONDS
					# Update sub-cart stats
					if not current_sub_filename.is_empty():
						data.carts[current_cart_key].sub_carts[current_sub_filename].seconds += UNIT_SECONDS
						
				elif c == "_" and is_in_play_session:
					data.carts[current_cart_key].seconds += UNIT_SECONDS
					# Update sub-cart stats
					if not current_sub_filename.is_empty():
						data.carts[current_cart_key].sub_carts[current_sub_filename].seconds += UNIT_SECONDS
				else:
					is_in_play_session = false

	# Update persistent timestamp
	if last_line_time > data.last_analyzed_time:
		data.last_analyzed_time = last_line_time
		_save_stats(data)
	
	# Update cache with final data
	ActivityLogAnalyzer.cached_data = data
		
	_print_report(data)
	
	# Trigger Background Metadata Enrichment
	# Ensure the class is loaded
	var metadata_cache = load("res://metadata_cache.gd")
	if metadata_cache:
		metadata_cache.run_enrichment_async(data)

# Helper to normalize cart names
# "game-0.p8.png" -> "game.p8.png" (or just "game")
static func _get_base_cart_name(filename: String) -> String:
	# 1. Strip extension (return just the name)
	var base = filename
	if filename.ends_with(".p8.png"):
		base = filename.left(filename.length() - 7)
	elif filename.ends_with(".p8"):
		base = filename.left(filename.length() - 3)
	
	# 2. Check for trailing numbers "-1", "-23" etc within the base name
	# Iterate backwards from end of base
	# "game-2" -> base="game"
	
	var regex = RegEx.new()
	regex.compile("^(.*)-(\\d+)$")
	var result = regex.search(base)
	if result:
		# Group 1 is the part before the dash-number
		return result.get_string(1)
		
	return base

func _load_stats() -> Dictionary:
	var default_data = {"last_analyzed_time": 0, "carts": {}}
	if not FileAccess.file_exists(STATS_FILE):
		return default_data
		
	var file = FileAccess.open(STATS_FILE, FileAccess.READ)
	if not file: return default_data
	
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	if err != OK: return default_data
	
	return json.data

func _save_stats(data: Dictionary):
	var file = FileAccess.open(STATS_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))

func _print_report(data: Dictionary):
	print("\n--- PICO-8 Activity Report ---")
	
	# Convert dict to array for sorting
	var list = []
	for name in data.carts:
		var entry = data.carts[name]
		list.append({"name": name, "seconds": int(entry.get("seconds", 0)), "launches": int(entry.get("launches", 0))})
	
	# Sort by Seconds descending
	list.sort_custom(func(a, b): return int(a.get("seconds", 0)) > int(b.get("seconds", 0)))
	
	#print("%-30s | %-10s | %s" % ["Cart Name", "Time", "Launches"])
	#print("----------------------------------------------------------")
	#
	#for item in list:
	#	var time_str = _fmt_time(item.seconds)
	#	print("%-30s | %-10s | %d" % [item.name.left(30), time_str, item.launches])		
	#print("----------------------------------------------------------\n")

func _fmt_time(total_seconds: int) -> String:
	var h = total_seconds / 3600
	var m = (total_seconds % 3600) / 60
	var s = total_seconds % 60
	if h > 0:
		return "%dh %02dm" % [h, m]
	return "%02dm %02ds" % [m, s]

static func _rebuild_lookup(data: Dictionary):
	file_lookup.clear()
	if not data.has("carts"): return
	
	for key in data.carts:
		var entry = data.carts[key]
		if entry.has("sub_carts"):
			for sub in entry.sub_carts:
				file_lookup[sub] = key
