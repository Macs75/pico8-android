extends TextureRect
class_name BezelOverlay

# Constants
const BEZEL_FILENAME = "bezel.png"
const HOLE_ALPHA_THRESHOLD = 0.1 # Alpha value below which a pixel is considered transparent

# State
var detected_hole_rect: Rect2 = Rect2()
var is_bezel_loaded: bool = false
var original_texture_size: Vector2 = Vector2.ZERO
var original_image: Image = null
var original_texture: Texture2D = null

var _resize_timer: Timer = null

func _ready():
	# Configure self
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100 # Ensure it sits above the game display
	
	# Setup Debounce Timer
	_resize_timer = Timer.new()
	_resize_timer.one_shot = true
	_resize_timer.wait_time = 0.5 # Wait for rotation/resize to settle
	_resize_timer.timeout.connect(_perform_high_quality_resize)
	add_child(_resize_timer)
	
	# Attempt to load bezel
	print("BezelOverlay: _ready called. Waiting for scene tree before loading...")
	# Defer loading to ensure parent is ready for layout updates
	call_deferred("load_external_bezel")

func load_external_bezel():
	var bezel_path = PicoBootManager.PUBLIC_FOLDER + "/" + BEZEL_FILENAME
	print("BezelOverlay: Attempting to load bezel from: ", bezel_path)
	
	if FileAccess.file_exists(bezel_path):
		var image = Image.load_from_file(bezel_path)
		if image:
			print("BezelOverlay: Loaded custom bezel image. Size: ", image.get_size())
			original_image = image # Store original for high-quality resizing
			
			original_texture = ImageTexture.create_from_image(image)
			self.texture = original_texture
			original_texture_size = Vector2(image.get_width(), image.get_height())
			
			# Detect the transparent hole
			detect_hole(image)
			is_bezel_loaded = true
			
			# Initial layout update
			if get_parent() and get_parent().has_method("get_display_rect"):
				var rect = get_parent().get_display_rect()
				print("BezelOverlay: Initial Game Rect: ", rect)
				update_layout(rect)
			else:
				print("BezelOverlay: Parent missing or invalid, cannot position bezel yet. Parent: ", get_parent())
		else:
			print("BezelOverlay: Failed to load image data from file")
	else:
		print("BezelOverlay: No custom bezel found at ", bezel_path)
		is_bezel_loaded = false
		self.texture = null
		
		# List files in the directory for debugging
		var dir = DirAccess.open(PicoBootManager.PUBLIC_FOLDER)
		if dir:
			dir.list_dir_begin()
			var file_name = dir.get_next()
			print("BezelOverlay: Listing files in ", PicoBootManager.PUBLIC_FOLDER, ":")
			while file_name != "":
				print(" - ", file_name)
				file_name = dir.get_next()
		else:
			print("BezelOverlay: Could not access PUBLIC_FOLDER to list files")

func detect_hole(img: Image):
	var w = img.get_width()
	var h = img.get_height()
	
	# Start scan from center (float division to avoid lint warning, cast to int)
	var center_x = int(w / 2.0)
	var center_y = int(h / 2.0)
	
	print("BezelOverlay: Scanning for hole starting at center: ", center_x, ",", center_y)
	
	# Verify center is transparent (or find nearest transparent pixel)
	
	var start_pixel = img.get_pixel(center_x, center_y)
	if start_pixel.a > HOLE_ALPHA_THRESHOLD:
		print("BezelOverlay: Center pixel is opaque! Searching for hole...")
		detected_hole_rect = Rect2(0, 0, w, h)
		return

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
		
	# Adjust bounds (pixels are 0-indexed)
	var hole_x = left + 1
	var hole_y = top + 1
	var hole_w = (right - 1) - hole_x + 1
	var hole_h = (bottom - 1) - hole_y + 1
	
	detected_hole_rect = Rect2(hole_x, hole_y, hole_w, hole_h)
	print("BezelOverlay: Detected hole rect: ", detected_hole_rect)

func update_layout(game_display_rect: Rect2):
	if not is_bezel_loaded or original_image == null:
		return
		
	if detected_hole_rect.size.x == 0 or detected_hole_rect.size.y == 0:
		return
		
	# Calculate required scale factors to match hole to game rect
	var scale_x = game_display_rect.size.x / detected_hole_rect.size.x
	var scale_y = game_display_rect.size.y / detected_hole_rect.size.y
	
	# Use the larger offset to ensure coverage? No, we want exact fit.
	# Scale is simple ratio.
	var final_scale = Vector2(scale_x, scale_y)
	
	# Calculate new target size (rounded to int pixels)
	var target_size = (original_texture_size * final_scale).round()
	
	# Ensure Control size matches (though texture dictates it mostly)
	self.size = target_size
	
	# Position the bezel so the hole aligns with the game rect
	# We want position such that: position + (detected_hole_rect.position * final_scale) == game_display_rect.position
	
	var hole_offset_scaled = detected_hole_rect.position * final_scale
	var bezel_pos = game_display_rect.position - hole_offset_scaled
	
	self.position = bezel_pos
	self.size = target_size
	
	# Handle Texture Quality
	var current_tex_size = texture.get_size() if texture else Vector2.ZERO
	# Use a small tolerance
	if current_tex_size.distance_to(target_size) > 1.0:
		# Mismatch!
	# 1. Reset to standard quality immediately (if timer not running)
		if _resize_timer.is_stopped() and original_texture:
			self.texture = original_texture
		
		# 2. Schedule High-Res
		_resize_timer.start()

func _perform_high_quality_resize():
	# Perform High-Quality Resize based on current layout
	if not original_image: return
	
	# Use our own current size as the target, assuming update_layout set it correctly
	var target_size = self.size
	if target_size == Vector2.ZERO: return

	# print("BezelOverlay: Performing High-Quality Resize to ", target_size)
	var resized_img = original_image.duplicate()
	resized_img.resize(int(target_size.x), int(target_size.y), Image.INTERPOLATE_CUBIC)
	self.texture = ImageTexture.create_from_image(resized_img)
