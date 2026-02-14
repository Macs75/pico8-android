extends TextureRect
class_name BezelOverlay

# Constants
const BEZEL_FILENAME = "bezel.png"
const BEZEL_LANDSCAPE_FILENAME = "bezel_landscape.png"
const BEZEL_PORTRAIT_FILENAME = "bezel_portrait.png"
const HOLE_ALPHA_THRESHOLD = 0.1 # Alpha value below which a pixel is considered transparent

class BezelCacheEntry:
	var original_image: Image
	var hole_rect: Rect2
	var texture_cache: Dictionary = {} # Vector2(size) -> ImageTexture
	var mod_time: int = 0

var _cache: Dictionary = {} # String(path) -> BezelCacheEntry
var _current_entry: BezelCacheEntry = null

var _hq_timer: Timer = null
var _pending_target_size: Vector2 = Vector2.ZERO

var is_bezel_loaded: bool:
	get:
		return _current_entry != null

func _ready():
	# Configure self
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100 # Ensure it sits above the game display
	
	_hq_timer = Timer.new()
	_hq_timer.one_shot = true
	_hq_timer.wait_time = 0.5
	_hq_timer.timeout.connect(_finalize_high_quality_resize)
	add_child(_hq_timer)
	
	# Preload BOTH orientations
	var path_l = _get_bezel_path_for_orientation(true)
	_preload_bezel(path_l)
	
	var path_p = _get_bezel_path_for_orientation(false)
	_preload_bezel(path_p)

# ... (Helper Functions) ...

var _resolved_path_cache: Dictionary = {} # bool(is_landscape) -> String

func _get_bezel_path_for_orientation(is_landscape: bool) -> String:
	if _resolved_path_cache.has(is_landscape):
		return _resolved_path_cache[is_landscape]
		
	var target_file = BEZEL_LANDSCAPE_FILENAME if is_landscape else BEZEL_PORTRAIT_FILENAME
	# Use ThemeManager to resolve path
	var path = ThemeManager.get_resource_path(target_file)
	if path == "":
		# Fallback (ThemeManager should handle this, but for safety)
		path = PicoBootManager.PUBLIC_FOLDER + "/" + BEZEL_FILENAME
	
	_resolved_path_cache[is_landscape] = path
	return path

func _ensure_bezel_loaded(is_landscape: bool):
	var needed_path = _get_bezel_path_for_orientation(is_landscape)
	# Always attempt load, which now checks timestamp internally
	_load_bezel_from_path(needed_path)

func _preload_bezel(path: String):
	if not FileAccess.file_exists(path):
		# If file missing, clear cache entry if it existed
		if _cache.has(path):
			_cache.erase(path)
		return

	var current_mod_time = FileAccess.get_modified_time(path)
	
	# Check for Cache Hit (File matches cached entry)
	if _cache.has(path):
		var entry = _cache[path]
		if entry.mod_time == current_mod_time:
			# Up to date
			return
		else:
			print("BezelOverlay: File changed, reloading: ", path)
	
	# Load new
	var image = Image.load_from_file(path)
	if image:
		print("BezelOverlay: Loaded bezel: ", path)
		var entry = BezelCacheEntry.new()
		entry.original_image = image
		entry.hole_rect = _detect_hole(image)
		entry.mod_time = current_mod_time
		_cache[path] = entry
	else:
		print("BezelOverlay: Failed to load image: ", path)

func _load_bezel_from_path(bezel_path: String):
	# Now just a cache lookup or lazy load
	if not _cache.has(bezel_path):
		_preload_bezel(bezel_path)
		
	if _cache.has(bezel_path):
		var prev_entry = _current_entry
		_current_entry = _cache[bezel_path]
		
		# Trigger update only if changed or initial
		if prev_entry != _current_entry and get_parent() and get_parent().has_method("get_display_rect"):
			var rect = get_parent().get_display_rect()
			update_layout(rect)
	else:
		_current_entry = null
		self.texture = null

func _detect_hole(img: Image) -> Rect2:
	var w = img.get_width()
	var h = img.get_height()
	
	# Start scan from center
	var center_x = int(w / 2.0)
	var center_y = int(h / 2.0)
	
	# Verify center is transparent
	var start_pixel = img.get_pixel(center_x, center_y)
	if start_pixel.a > HOLE_ALPHA_THRESHOLD:
		print("BezelOverlay: Center pixel is opaque! Searching for hole...")
		return Rect2(0, 0, w, h)

	# Scan Right
	var right = center_x
	while right < w:
		if img.get_pixel(right, center_y).a > HOLE_ALPHA_THRESHOLD:
			break
		right += 1
		
	# Scan Left
	var left = center_x
	while left >= 0:
		if img.get_pixel(left, center_y).a > HOLE_ALPHA_THRESHOLD:
			break
		left -= 1
		
	# Scan Down
	var bottom = center_y
	while bottom < h:
		if img.get_pixel(center_x, bottom).a > HOLE_ALPHA_THRESHOLD:
			break
		bottom += 1
		
	# Scan Up
	var top = center_y
	while top >= 0:
		if img.get_pixel(center_x, top).a > HOLE_ALPHA_THRESHOLD:
			break
		top -= 1
		
	# Adjust bounds
	var hole_x = left + 1
	var hole_y = top + 1
	var hole_w = (right - 1) - hole_x + 1
	var hole_h = (bottom - 1) - hole_y + 1
	
	var r = Rect2(hole_x, hole_y, hole_w, hole_h)
	# print("BezelOverlay: Detected hole rect: ", r)
	return r

func update_layout(game_display_rect: Rect2):
	# Check orientation and ensure correct bezel is loaded
	var is_landscape = PicoVideoStreamer.is_system_landscape()
	_ensure_bezel_loaded(is_landscape)

	if not _current_entry:
		return
		
	var hole_rect = _current_entry.hole_rect
	if hole_rect.size.x == 0 or hole_rect.size.y == 0:
		return
		
	# Calculate required scale factors to match hole to game rect
	var scale_x = game_display_rect.size.x / hole_rect.size.x
	var scale_y = game_display_rect.size.y / hole_rect.size.y
	
	var final_scale = Vector2(scale_x, scale_y)
	
	# Calculate new target size (rounded to int pixels)
	var original_size = Vector2(_current_entry.original_image.get_width(), _current_entry.original_image.get_height())
	var target_size = (original_size * final_scale).round()
	
	# Position the bezel
	var hole_offset_scaled = hole_rect.position * final_scale
	var bezel_pos = game_display_rect.position - hole_offset_scaled
	
	self.position = bezel_pos
	self.size = target_size
	
	# --- Caching & Resize Logic ---
	
	# Check Cache First
	if _current_entry.texture_cache.has(target_size):
		if self.texture != _current_entry.texture_cache[target_size]:
			# print("BezelOverlay: Cache HIT for ", target_size)
			self.texture = _current_entry.texture_cache[target_size]
			_hq_timer.stop() # Cancel any pending resizes
		return
		
	# Cache Miss: Trigger Resize
	_pending_target_size = target_size
	
	# Fast Resize (Immediate)
	var fast_img = _current_entry.original_image.duplicate()
	fast_img.resize(int(target_size.x), int(target_size.y), Image.INTERPOLATE_NEAREST)
	self.texture = ImageTexture.create_from_image(fast_img)
	
	# Queue HQ Resize
	_hq_timer.start()

func _perform_high_quality_resize():
	# DEPRECATED: Logic moved to update_layout and _finalize
	pass

func _finalize_high_quality_resize():
	if not _current_entry or not _current_entry.original_image: return
	var target_size = _pending_target_size
	if target_size == Vector2.ZERO: return
	
	# Double check if we already cached this while waiting (unlikely but safe)
	if _current_entry.texture_cache.has(target_size):
		self.texture = _current_entry.texture_cache[target_size]
		return
	
	# print("BezelOverlay: Finalizing High-Quality Resize (Lanczos) to ", target_size)
	var hq_img = _current_entry.original_image.duplicate()
	hq_img.resize(int(target_size.x), int(target_size.y), Image.INTERPOLATE_LANCZOS)
	var tex = ImageTexture.create_from_image(hq_img)
	
	self.texture = tex
	# Store in cache
	_current_entry.texture_cache[target_size] = tex
