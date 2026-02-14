extends RefCounted
class_name LayoutHelper

static func is_in_landscape_ui(node: Node) -> bool:
	var p = node.get_parent()
	while p:
		if p.name == "LandscapeUI":
			return true
		p = p.get_parent()
	return false

static func apply_layout(node: Control, bezel_rect: Rect2):
	# Optimization: Only update if actually visible
	if not node.is_visible_in_tree(): return

	var is_landscape = is_in_landscape_ui(node)
	
	# 1. User Override Check
	var user_pos = PicoVideoStreamer.get_control_pos(node.name, is_landscape)
	if user_pos != null:
		print(node.name, ": Skipping theme layout due to user override.")
		return
		
	# 2. Theme Layout Application
	var layout = ThemeManager.get_theme_layout(is_landscape)
	if layout.is_empty(): return
	
	var layout_key = get_layout_key_for_node(node.name)
	
	if layout.has("controls") and layout["controls"].has(layout_key):
		var control_data = layout["controls"][layout_key]
		if layout.has("bezel_size"):
			var bz = layout["bezel_size"]
			var theme_bezel_size = Vector2(bz[0], bz[1])
			
			# Safety check for required fields
			if not control_data.has("x") or not control_data.has("y"):
				return
				
			var theme_pos = Vector2(control_data["x"], control_data["y"])
			
			var global_target_pos = PicoVideoStreamer.transform_theme_pos(theme_pos, theme_bezel_size, bezel_rect)
			
			print(node.name, ": Theme applied. ", theme_pos, " -> Global ", global_target_pos)
			var parent = node.get_parent()
			if parent:
				node.position = parent.get_global_transform().affine_inverse() * global_target_pos

static func save_layout(node: Control, original_scale_x: float):
	var current_scale_mod = node.scale.x / original_scale_x
	PicoVideoStreamer.set_control_layout_data(node.name, node.position, current_scale_mod, is_in_landscape_ui(node))

static func get_layout_key_for_node(node_name: String) -> String:
	match node_name:
		"Pause": return "menu"
		"Escape": return "escape"
		_: return node_name
