extends Node
class_name FavouritesManager

const PICO8_DATA_PATH = "/sdcard/Documents/pico8/data"
const FAVOURITES_FILENAME = "favourites.txt"

class FavouriteItem:
	var raw_line: String = ""
	var cart_id: String = "" # Col 1
	var key: String = "" # Col 2
	var pid: String = ""
	var author: String = "" # Col 4
	var filename: String = "" # Col 5
	var name: String = "" # Last Col
	
	func _init(line: String):
		raw_line = line
		var parts = line.split("|")
		
		# Format example:
		# |col1 (ID)     |col2 (Key)     |col3 (PID?) |col4 (Author) |col5 (File) |Name
		
		# Parts array (split by | causes empty [0]):
		# [0] ""
		# [1] ID
		# [2] Key
		# [3] PID
		# [4] Author
		# [5] Filename?
		# [6] Name
		
		if parts.size() > 1:
			cart_id = parts[1].strip_edges()

		if parts.size() > 2:
			key = parts[2].strip_edges()
			
		if parts.size() > 4:
			author = parts[4].strip_edges()

		if parts.size() > 5:
			filename = parts[5].strip_edges()
			
		if parts.size() > 1:
			name = parts[parts.size() - 1].strip_edges()
			
	func _to_string():
		return "%s by %s" % [name, author]

static func get_favourites_file_path() -> String:
	# Use PicoBootManager for consistent path access if available, else fallback
	if ClassDB.class_exists("PicoBootManager"):
		return PicoBootManager.PUBLIC_FOLDER + "/data/" + FAVOURITES_FILENAME
	return PICO8_DATA_PATH + "/" + FAVOURITES_FILENAME

static func load_favourites() -> Array[FavouriteItem]:
	var items: Array[FavouriteItem] = []
	var path = get_favourites_file_path()
	
	if not FileAccess.file_exists(path):
		print("FavouritesManager: File not found at: ", path)
		return items
		
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		print("FavouritesManager: Failed to open file: ", FileAccess.get_open_error())
		return items
		
	while not file.eof_reached():
		var line = file.get_line()
		if line.strip_edges().is_empty():
			continue
			
		var item = FavouriteItem.new(line)
		items.append(item)
		
	return items

static func save_favourites(items: Array[FavouriteItem]) -> bool:
	var path = get_favourites_file_path()
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		print("FavouritesManager: Failed to write file: ", FileAccess.get_open_error())
		return false
		
	for item in items:
		file.store_line(item.raw_line)
		
	return true
