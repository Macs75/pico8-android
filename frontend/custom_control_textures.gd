extends Node

# CustomControlTextures
# Manages loading custom textures for on-screen controls from /Documents/pico8

# Returns [normal_texture, pressed_texture] or [null, null] if not found
# If pressed texture not found, returns [normal_texture, null] to disable press effect
static func get_custom_textures(control_name: String, is_landscape: bool) -> Array:
	var suffix = "_landscape" if is_landscape else "_portrait"
	var normal_tex: Texture2D = null
	var pressed_tex: Texture2D = null
	
	# Try orientation-specific first
	var specific_normal = ThemeManager.get_resource_path(control_name + suffix + ".png")
	var specific_pressed = ThemeManager.get_resource_path(control_name + suffix + "_pressed.png")
	
	print("CustomControlTextures: Checking ", specific_normal)
	if specific_normal != "" and FileAccess.file_exists(specific_normal):
		print("  -> Found!")
		var img = Image.load_from_file(specific_normal)
		if img:
			var tex = ImageTexture.create_from_image(img)
			# Disable mipmaps for crisp rendering at any scale
			tex.set_meta("no_mipmap", true)
			normal_tex = tex
		
		# Only check pressed if normal found (or independent? current logic implies pairs)
		if specific_pressed != "" and FileAccess.file_exists(specific_pressed):
			print("  -> Found pressed variant too!")
			var img_pressed = Image.load_from_file(specific_pressed)
			if img_pressed:
				var tex_pressed = ImageTexture.create_from_image(img_pressed)
				tex_pressed.set_meta("no_mipmap", true)
				pressed_tex = tex_pressed
		
		return [normal_tex, pressed_tex]
	
	# Fallback to generic (no orientation suffix)
	var generic_normal = ThemeManager.get_resource_path(control_name + ".png")
	var generic_pressed = ThemeManager.get_resource_path(control_name + "_pressed.png")
	
	if generic_normal != "" and FileAccess.file_exists(generic_normal):
		var img = Image.load_from_file(generic_normal)
		if img:
			var tex = ImageTexture.create_from_image(img)
			tex.set_meta("no_mipmap", true)
			normal_tex = tex
		
		if generic_pressed != "" and FileAccess.file_exists(generic_pressed):
			var img_pressed = Image.load_from_file(generic_pressed)
			if img_pressed:
				var tex_pressed = ImageTexture.create_from_image(img_pressed)
				tex_pressed.set_meta("no_mipmap", true)
				pressed_tex = tex_pressed
		
		return [normal_tex, pressed_tex]
	
	return [null, null]
