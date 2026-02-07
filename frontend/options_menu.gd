extends CanvasLayer

@onready var panel = $SlidePanel
@onready var edge_handler = $EdgeHandler

const ANIM_DURATION = 0.3
const EDGE_THRESHOLD = 50.0

var panel_width = 250.0

var is_open: bool = false
var audio_backend: String = "sles" # Default to sles
var custom_root_path: String = ""
var touch_start_x = 0.0
var is_dragging = false
var connected_controllers_dialog_scene = preload("res://connected_controllers_dialog.tscn")
var favourites_editor_scene = preload("res://favourites_editor.tscn")

# Swipe to Open Variables
var edge_drag_start = Vector2.ZERO
var is_edge_dragging = false
var swipe_threshold = 50.0

const CONFIG_PATH = "user://settings.cfg"

func _ready() -> void:
	# Hide immediately to prevent flash
	if panel:
		panel.position.x = -2000.0
	
	# Load config first to set initial state correctly
	load_config()

	# Connect UI Signals
	# Toggles
	if not %ToggleHaptic.toggled.is_connected(_on_haptic_toggled):
		%ToggleHaptic.toggled.connect(_on_haptic_toggled)
	if not %ToggleKeyboard.toggled.is_connected(_on_keyboard_toggled):
		%ToggleKeyboard.toggled.connect(_on_keyboard_toggled)
	if not %ToggleSwapZX.toggled.is_connected(_on_swap_zx_toggled):
		%ToggleSwapZX.toggled.connect(_on_swap_zx_toggled)
	if not %ToggleIntegerScaling.toggled.is_connected(_on_integer_scaling_toggled):
		%ToggleIntegerScaling.toggled.connect(_on_integer_scaling_toggled)
	if not %ToggleShowControls.toggled.is_connected(_on_show_controls_toggled):
		%ToggleShowControls.toggled.connect(_on_show_controls_toggled)
	if not %ToggleBezel.toggled.is_connected(_on_bezel_toggled):
		%ToggleBezel.toggled.connect(_on_bezel_toggled)
	if not %ShaderSelect.item_selected.is_connected(_on_shader_selected):
		%ShaderSelect.item_selected.connect(_on_shader_selected)
	if not %ColorPickerBG.color_changed.is_connected(_on_bg_color_picked):
		%ColorPickerBG.color_changed.connect(_on_bg_color_picked)

	# Labels (tap to toggle) - Now using Buttons
	%ButtonHaptic.pressed.connect(_on_label_pressed.bind(%ToggleHaptic))
	%ButtonSwapZX.pressed.connect(_on_label_pressed.bind(%ToggleSwapZX))
	%ButtonKeyboard.pressed.connect(_on_label_pressed.bind(%ToggleKeyboard))
	%ButtonIntegerScaling.pressed.connect(_on_label_pressed.bind(%ToggleIntegerScaling))
	%ButtonBezel.pressed.connect(_on_label_pressed.bind(%ToggleBezel))
	%ButtonShowControls.pressed.connect(_on_label_pressed.bind(%ToggleShowControls))
	%ButtonShaderSelect.pressed.connect(_on_shader_button_pressed)
	%ButtonConnectedControllers.pressed.connect(_on_connected_controllers_pressed)
	%ButtonBgColor.pressed.connect(func(): %ColorPickerBG.get_popup().popup_centered())
	

	%ButtonSelectRoot.pressed.connect(_on_select_root_pressed)
	%ButtonClearRoot.pressed.connect(_on_clear_root_pressed)
	
	if %ButtonFavourites:
		%ButtonFavourites.pressed.connect(_on_favourites_pressed)
	
	%ButtonInputMode.pressed.connect(_on_label_pressed.bind(%ToggleInputMode))
	
	if not %ToggleInputMode.toggled.is_connected(_on_input_mode_toggled):
		%ToggleInputMode.toggled.connect(_on_input_mode_toggled)
		
	if not %ToggleReposition.toggled.is_connected(_on_reposition_toggled):
		%ToggleReposition.toggled.connect(_on_reposition_toggled)
	%ButtonCustomizeLayout.pressed.connect(_on_label_pressed.bind(%ToggleReposition))


	if not %SliderSensitivity.value_changed.is_connected(_on_sensitivity_changed):
		%SliderSensitivity.value_changed.connect(_on_sensitivity_changed)

	if not %SliderSaturation.value_changed.is_connected(_on_saturation_changed):
		%SliderSaturation.value_changed.connect(_on_saturation_changed)
	
	if not %ButtonSaturationMinus.pressed.is_connected(_on_saturation_minus):
		%ButtonSaturationMinus.pressed.connect(_on_saturation_minus)
	
	if not %ButtonSaturationPlus.pressed.is_connected(_on_saturation_plus):
		%ButtonSaturationPlus.pressed.connect(_on_saturation_plus)
	
	if not %SliderButtonHue.value_changed.is_connected(_on_button_hue_changed):
		%SliderButtonHue.value_changed.connect(_on_button_hue_changed)
	
	if not %ButtonHueMinus.pressed.is_connected(_on_button_hue_minus):
		%ButtonHueMinus.pressed.connect(_on_button_hue_minus)
	
	if not %ButtonHuePlus.pressed.is_connected(_on_button_hue_plus):
		%ButtonHuePlus.pressed.connect(_on_button_hue_plus)
	
	if not %SliderButtonSat.value_changed.is_connected(_on_button_sat_changed):
		%SliderButtonSat.value_changed.connect(_on_button_sat_changed)
	
	if not %ButtonSatMinus.pressed.is_connected(_on_button_sat_minus):
		%ButtonSatMinus.pressed.connect(_on_button_sat_minus)
	
	if not %ButtonSatPlus.pressed.is_connected(_on_button_sat_plus):
		%ButtonSatPlus.pressed.connect(_on_button_sat_plus)
	
	if not %SliderButtonLight.value_changed.is_connected(_on_button_light_changed):
		%SliderButtonLight.value_changed.connect(_on_button_light_changed)
	
	if not %ButtonLightMinus.pressed.is_connected(_on_button_light_minus):
		%ButtonLightMinus.pressed.connect(_on_button_light_minus)
	
	if not %ButtonLightPlus.pressed.is_connected(_on_button_light_plus):
		%ButtonLightPlus.pressed.connect(_on_button_light_plus)

	%ButtonAppSettings.pressed.connect(_on_app_settings_pressed)
	if %ButtonSupport:
		%ButtonSupport.pressed.connect(_on_support_pressed)
	%ButtonSave.pressed.connect(save_config)
	
	%BtnDisplayToggle.pressed.connect(_on_section_toggled.bind(%BtnDisplayToggle, %ContainerDisplay))
	%BtnControlsToggle.pressed.connect(_on_section_toggled.bind(%BtnControlsToggle, %ContainerControls))
	%BtnAudioToggle.pressed.connect(_on_section_toggled.bind(%BtnAudioToggle, %ContainerAudio))
	%BtnOfflineToggle.pressed.connect(_on_section_toggled.bind(%BtnOfflineToggle, %ContainerOffline))
	%BtnToolsToggle.pressed.connect(_on_section_toggled.bind(%BtnToolsToggle, %ContainerTools))
	
	if %ButtonPlayStats:
		%ButtonPlayStats.pressed.connect(_on_play_stats_pressed)


	# Connect Audio Backend Label
	%ButtonAudioBackendLabel.pressed.connect(_on_label_pressed.bind(%ToggleAudioBackend))
	if not %ToggleAudioBackend.toggled.is_connected(_on_audio_backend_toggled):
		%ToggleAudioBackend.toggled.connect(_on_audio_backend_toggled)
	
	# Settings are applied via load_config(), no need to manually set button_pressed here if sync works
	# But we need to ensure the UI reflects the loaded state.
	# load_config handles: PicoVideoStreamer settings update AND UI element update.
	
	var app_version = ProjectSettings.get_setting("application/config/version")
	if app_version:
		%VersionLabel.text = "v" + str(app_version)
	else:
		%VersionLabel.text = "v1.0"
	
	# Subscribe to external changes
	KBMan.subscribe(_on_external_keyboard_change)
	
	# Listen for screen resize to update layout/orientation
	get_tree().root.size_changed.connect(_update_layout)
	
	# Edge Handler - Connect for Swipe-to-Open
	if edge_handler:
		edge_handler.gui_input.connect(_on_edge_handler_input)

	# Initial Layout Update
	_update_layout()
	
	# ROBUST FIX: Connect to visibility changes of siblings
	await get_tree().process_frame
	
	var main = get_node_or_null("/root/Main")
	if main:
		var arranger = main.get_node_or_null("Arranger")
		if arranger:
			if not arranger.visibility_changed.is_connected(_update_layout_deferred):
				arranger.visibility_changed.connect(_update_layout_deferred)
				
		var landscape_ui = main.get_node_or_null("LandscapeUI")
		if landscape_ui:
			if not landscape_ui.visibility_changed.is_connected(_update_layout_deferred):
				landscape_ui.visibility_changed.connect(_update_layout_deferred)

	# Trigger layout update again
	_update_layout()
	panel.position.x = - panel.size.x
	
	# Default sections to collapsed
	_on_section_toggled(%BtnControlsToggle, %ContainerControls)
	_on_section_toggled(%BtnAudioToggle, %ContainerAudio)
	_on_section_toggled(%BtnOfflineToggle, %ContainerOffline)

func _update_layout_deferred():
	call_deferred("_update_layout")

func _update_layout():
	var viewport_size = get_viewport().get_visible_rect().size
	
	# Resize Edge Handler dynamically (e.g. 6% of screen width, min 60px)
	if edge_handler:
		# Reset anchors to Left-Wide
		edge_handler.set_anchors_preset(Control.PRESET_LEFT_WIDE, true)
		
		var edge_width = max(60.0, viewport_size.x * 0.10)
		
		# Prevent overlap with Left D-Pad (Onmipad)
		var main = get_node_or_null("/root/Main")
		if main:
			# Arranger check
			var arranger = main.get_node_or_null("Arranger")
			if arranger and arranger.visible:
				var dpad = arranger.get_node_or_null("kbanchor/kb_gaming/Onmipad")
				if dpad and dpad.is_visible_in_tree():
					var dpad_rect = dpad.get_global_rect()
					var dpad_left_x = dpad_rect.position.x
					
					if dpad_left_x < viewport_size.x * 0.5:
						var safe_limit = max(30.0, dpad_left_x - 20) # Min 30px width
						if edge_width > safe_limit:
							edge_width = safe_limit
		
			# LandscapeUI Check (Absolute Path)
			var landscape_ui = main.get_node_or_null("LandscapeUI")
			if landscape_ui and landscape_ui.visible:
				var dpad = landscape_ui.get_node_or_null("Control/LeftPad/Omnipad")
				if dpad and dpad.is_visible_in_tree():
					var dpad_rect = dpad.get_global_rect()
					var dpad_left_x = dpad_rect.position.x
					
					if dpad_left_x < viewport_size.x * 0.5:
						var safe_limit = max(30.0, dpad_left_x - 20) # Min 30px width
						if edge_width > safe_limit:
							edge_width = safe_limit

		edge_handler.custom_minimum_size.x = edge_width
		edge_handler.size.x = edge_width
		# Force vertical expansion just in case
		edge_handler.size.y = viewport_size.y
		edge_handler.position.y = 0
		
		# Set Swipe Threshold (e.g. 5% of screen width)
		# Make sure threshold isn't larger than the handler itself (or unreasonably large)
		swipe_threshold = max(50.0, viewport_size.x * 0.05)

	# Disable Full Keyboard option in landscape (pocketchip not visible)
	var is_landscape = PicoVideoStreamer.is_system_landscape()
	%ToggleKeyboard.disabled = is_landscape
	%ButtonKeyboard.disabled = is_landscape
	# Visually indicate disabled state if needed, but standard disabled style should suffice
	
	# Calculate dynamic font size
	# IMPROVED: Use min dimension to keep text readable in landscape
	# Base on 5% of smaller dimension, clamped to at least 24px
	var min_dim = min(viewport_size.x, viewport_size.y)
	var dynamic_font_size = int(max(24, min_dim * 0.04))
	
	# Scale Factors
	# Keep icon readable but scaled relative to the new small font
	var scale_factor = float(dynamic_font_size) / 10.0
	scale_factor = clamp(scale_factor, 1.2, 3.0)
	
	# --- Apply Styling & Scaling ---
	
	# 1. Main Options Header
	var header_label = $SlidePanel/ScrollContainer/VBoxContainer/Header/Label
	header_label.add_theme_font_size_override("font_size", dynamic_font_size)
	
	# Scale Icon
	var icon_size = dynamic_font_size * 1.3
	%Icon.custom_minimum_size = Vector2(icon_size, icon_size)
	
	%ContainerDisplay.add_theme_constant_override("margin_left", int(30 * scale_factor))
	%ContainerControls.add_theme_constant_override("margin_left", int(30 * scale_factor))
	%ContainerButtons.add_theme_constant_override("margin_left", int(30 * scale_factor))

	# 2. Haptic Row
	_style_option_row(%ButtonHaptic, %ToggleHaptic, $SlidePanel/ScrollContainer/VBoxContainer/SectionControls/ContainerControls/ContentControls/HapticRow/WrapperHaptic, dynamic_font_size, scale_factor)
	
	# 2a. Swap O/X Row
	_style_option_row(%ButtonSwapZX, %ToggleSwapZX, $SlidePanel/ScrollContainer/VBoxContainer/SectionControls/ContainerControls/ContentControls/SwapZXRow/WrapperSwapZX, dynamic_font_size, scale_factor)

	# 3. Keyboard Row
	_style_option_row(%ButtonKeyboard, %ToggleKeyboard, $SlidePanel/ScrollContainer/VBoxContainer/SectionControls/ContainerControls/ContentControls/KeyboardRow/WrapperKeyboard, dynamic_font_size, scale_factor)

	# 4. Integer Scaling Row
	_style_option_row(%ButtonIntegerScaling, %ToggleIntegerScaling, $SlidePanel/ScrollContainer/VBoxContainer/SectionDisplay/ContainerDisplay/ContentDisplay/IntegerScalingRow/WrapperIntegerScaling, dynamic_font_size, scale_factor)

	# 4a. Bezel Row
	_style_option_row(%ButtonBezel, %ToggleBezel, $SlidePanel/ScrollContainer/VBoxContainer/SectionDisplay/ContainerDisplay/ContentDisplay/BezelRow/WrapperBezel, dynamic_font_size, scale_factor)

	# 5. Show Controls Row
	_style_option_row(%ButtonShowControls, %ToggleShowControls, $SlidePanel/ScrollContainer/VBoxContainer/SectionControls/ContainerControls/ContentControls/ShowControlsRow/WrapperShowControls, dynamic_font_size, scale_factor)

	# 5a. Connected Controllers Row
	_style_option_row(%ButtonConnectedControllers, %ArrowConnectedControllers, $SlidePanel/ScrollContainer/VBoxContainer/SectionControls/ContainerControls/ContentControls/ConnectedControllersRow/WrapperConnectedControllers, dynamic_font_size, scale_factor)

	# 6. Background Color Row
	_style_option_row(%ButtonBgColor, %ColorPickerBG, $SlidePanel/ScrollContainer/VBoxContainer/SectionDisplay/ContainerDisplay/ContentDisplay/BgColorRow/WrapperBgColor, dynamic_font_size, scale_factor)

	# 6a. Shader Select Row
	_style_shader_select_row(%ButtonShaderSelect, %ShaderSelect, $SlidePanel/ScrollContainer/VBoxContainer/SectionDisplay/ContainerDisplay/ContentDisplay/ShaderSelectRow/WrapperShaderSelect, dynamic_font_size, scale_factor)

	# 6b. Reposition Row
	_style_option_row(%ButtonCustomizeLayout, %ToggleReposition, $SlidePanel/ScrollContainer/VBoxContainer/SectionDisplay/ContainerDisplay/ContentDisplay/RepositionRow/WrapperReposition, dynamic_font_size, scale_factor)

	# 6c. Audio Section Styles
	%BtnAudioToggle.add_theme_font_size_override("font_size", int(dynamic_font_size * 1.1))
	if %ContainerAudio:
		%ContainerAudio.add_theme_constant_override("margin_left", int(30 * scale_factor))
		
	_style_option_row(%ButtonAudioBackendLabel, %ToggleAudioBackend, $SlidePanel/ScrollContainer/VBoxContainer/SectionAudio/ContainerAudio/ContentAudio/AudioRow/WrapperAudioBackend, dynamic_font_size, scale_factor)

	# 7. Input Mode Row
	_style_option_row(%ButtonInputMode, %ToggleInputMode, $SlidePanel/ScrollContainer/VBoxContainer/SectionControls/ContainerControls/ContentControls/InputModeRow/WrapperInputMode, dynamic_font_size, scale_factor)

	# 7. Sensitivity Row
	%LabelSensitivity.add_theme_font_size_override("font_size", dynamic_font_size)
	%LabelSensitivityValue.add_theme_font_size_override("font_size", dynamic_font_size)
	# Scale slider custom minimum width?
	var slider = %SliderSensitivity
	var slider_scaler = %SliderScaler
	
	# Reset base size (unscaled)
	slider.scale = Vector2(scale_factor, scale_factor)
	
	# Adjust wrapper to hold scaled slider
	var scaled_size = slider.size * scale_factor
	slider_scaler.custom_minimum_size = scaled_size
	
	# 7a. Saturation Row
	%LabelSaturation.add_theme_font_size_override("font_size", dynamic_font_size)
	%LabelSaturationValue.add_theme_font_size_override("font_size", dynamic_font_size)
	%ButtonSaturationMinus.add_theme_font_size_override("font_size", dynamic_font_size)
	%ButtonSaturationPlus.add_theme_font_size_override("font_size", dynamic_font_size)
	
	var slider_sat = %SliderSaturation
	var slider_scaler_sat = %SliderScalerSaturation
	
	slider_sat.scale = Vector2(scale_factor, scale_factor)
	var scaled_size_sat = slider_sat.size * scale_factor
	slider_scaler_sat.custom_minimum_size = scaled_size_sat
	
	# 7b. Buttons Header
	%LabelButtonsHeader.add_theme_font_size_override("font_size", dynamic_font_size)
	
	# 7c. Button Hue Row
	%LabelButtonHue.add_theme_font_size_override("font_size", dynamic_font_size)
	%LabelButtonHueValue.add_theme_font_size_override("font_size", int(dynamic_font_size * 0.85))
	%ButtonHueMinus.add_theme_font_size_override("font_size", dynamic_font_size)
	%ButtonHuePlus.add_theme_font_size_override("font_size", dynamic_font_size)
	
	var slider_hue = %SliderButtonHue
	var slider_scaler_hue = %SliderScalerButtonHue
	
	slider_hue.scale = Vector2(scale_factor, scale_factor)
	var scaled_size_hue = slider_hue.size * scale_factor
	slider_scaler_hue.custom_minimum_size = scaled_size_hue
	
	# 7c. Button Saturation Row
	%LabelButtonSat.add_theme_font_size_override("font_size", dynamic_font_size)
	%LabelButtonSatValue.add_theme_font_size_override("font_size", int(dynamic_font_size * 0.85))
	%ButtonSatMinus.add_theme_font_size_override("font_size", dynamic_font_size)
	%ButtonSatPlus.add_theme_font_size_override("font_size", dynamic_font_size)
	
	var slider_sat2 = %SliderButtonSat
	var slider_scaler_sat2 = %SliderScalerButtonSat
	
	slider_sat2.scale = Vector2(scale_factor, scale_factor)
	var scaled_size_sat2 = slider_sat2.size * scale_factor
	slider_scaler_sat2.custom_minimum_size = scaled_size_sat2
	
	# 7d. Button Lightness Row
	%LabelButtonLight.add_theme_font_size_override("font_size", dynamic_font_size)
	%LabelButtonLightValue.add_theme_font_size_override("font_size", int(dynamic_font_size * 0.85))
	%ButtonLightMinus.add_theme_font_size_override("font_size", dynamic_font_size)
	%ButtonLightPlus.add_theme_font_size_override("font_size", dynamic_font_size)
	
	var slider_light = %SliderButtonLight
	var slider_scaler_light = %SliderScalerButtonLight
	
	slider_light.scale = Vector2(scale_factor, scale_factor)
	var scaled_size_light = slider_light.size * scale_factor
	slider_scaler_light.custom_minimum_size = scaled_size_light

	# 7e. Offline Section Styles
	%BtnOfflineToggle.add_theme_font_size_override("font_size", int(dynamic_font_size * 1.1))
	if %ContainerOffline:
		%ContainerOffline.add_theme_constant_override("margin_left", int(30 * scale_factor))
		
	%ButtonSelectRoot.add_theme_font_size_override("font_size", dynamic_font_size)
	%ButtonClearRoot.add_theme_font_size_override("font_size", dynamic_font_size)
	%LabelRootPath.add_theme_font_size_override("font_size", int(dynamic_font_size * 0.7)) # Smaller font for path
	_update_root_path_label() # Ensure label color/visible is correct
	
	if %ButtonFavourites:
		%ButtonFavourites.add_theme_font_size_override("font_size", dynamic_font_size)
	
	if %ButtonPlayStats:
		%ButtonPlayStats.add_theme_font_size_override("font_size", dynamic_font_size)

	# 7f. Tools Section Styles
	%BtnToolsToggle.add_theme_font_size_override("font_size", int(dynamic_font_size * 1.1))
	if %ContainerTools:
		%ContainerTools.add_theme_constant_override("margin_left", int(30 * scale_factor))


	# 4. Save Buttons
	%ButtonAppSettings.add_theme_font_size_override("font_size", dynamic_font_size)
	if %ButtonSupport:
		%ButtonSupport.add_theme_font_size_override("font_size", dynamic_font_size)
		# Ensure icon scales comfortably with text
		# Godot's expand_icon fits to height, which follows font size mostly
	%ButtonSave.add_theme_font_size_override("font_size", dynamic_font_size)
	
	%ButtonSave.add_theme_font_size_override("font_size", dynamic_font_size)
	
	# 5. Version Label (slightly smaller)
	%VersionLabel.add_theme_font_size_override("font_size", max(10, int(dynamic_font_size * 0.8)))

	# --- Tooltip Scaling ---
	# Ensure tooltips are readable on high-DPI screens
	var tooltip_font_size = int(dynamic_font_size * 0.9)
	
	# Create or get theme for the SlidePanel so all children inherit these tooltip settings
	var menu_theme = panel.theme
	if not menu_theme:
		menu_theme = Theme.new()
		panel.theme = menu_theme
	
	# Set font size for TooltipLabel type
	menu_theme.set_font_size("font_size", "TooltipLabel", tooltip_font_size)
	
	# Add some padding to the tooltip panel for better readability
	var tooltip_style = StyleBoxFlat.new()
	tooltip_style.bg_color = Color(0.15, 0.15, 0.15, 0.9) # Dark grey semi-transparent
	tooltip_style.border_width_left = 2
	tooltip_style.border_width_top = 2
	tooltip_style.border_width_right = 2
	tooltip_style.border_width_bottom = 2
	tooltip_style.border_color = Color(0.3, 0.3, 0.3, 1.0) # Lighter grey border
	tooltip_style.set_content_margin_all(int(10 * scale_factor))
	tooltip_style.corner_radius_top_left = 4
	tooltip_style.corner_radius_top_right = 4
	tooltip_style.corner_radius_bottom_left = 4
	tooltip_style.corner_radius_bottom_right = 4
	
	menu_theme.set_stylebox("panel", "TooltipPanel", tooltip_style)

	# --- Style Accordion Headers ---
	var header_font_size = int(dynamic_font_size * 1.1)
	%BtnDisplayToggle.add_theme_font_size_override("font_size", header_font_size)
	%BtnControlsToggle.add_theme_font_size_override("font_size", header_font_size)
	%BtnOfflineToggle.add_theme_font_size_override("font_size", header_font_size)
	%BtnToolsToggle.add_theme_font_size_override("font_size", header_font_size)


	# --- Resize Panel ---
	# Wait for layout to process to get correct width
	await get_tree().process_frame
	
	# Adjust panel width if content is wider (due to scaling)
	var content_min_width = $SlidePanel/ScrollContainer/VBoxContainer.get_combined_minimum_size().x
	# Add some padding (margin of proper fit)
	var required_width = content_min_width + 10
	# Minimum safe width
	var final_width = max(required_width, min(500, viewport_size.x * 0.5))
	
	panel.size.x = final_width
	if is_open:
		panel.position.x = 0
	else:
		panel.position.x = - final_width
		
	# Resize Color Picker Popup
	if %ColorPickerBG:
		var popup = %ColorPickerBG.get_picker().get_window() if %ColorPickerBG.get_picker().get_window() else %ColorPickerBG.get_popup()
		if not popup:
			popup = %ColorPickerBG.get_popup()
			
			
		# Set a reasonable base size (Reduced 30% further)
		var base_w = 175.0
		var base_h = 245.0
		var picker = %ColorPickerBG.get_picker()
		picker.custom_minimum_size = Vector2(base_w, base_h)
		popup.size = Vector2(base_w, base_h)
		
		# Calculate Safe Scale
		# Ensure base_h * scale <= viewport_size.y * 0.85 (more margin)
		var max_scale_y = (viewport_size.y * 0.4) / base_h
		var max_scale_x = (viewport_size.x * 0.4) / base_w
		var safe_scale = min(scale_factor, min(max_scale_x, max_scale_y))
		
		# Enable standard window scaling with clamp
		popup.content_scale_factor = safe_scale
		popup.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		
		# Remove previous manual font override to avoid double-scaling if window scale works
		picker.remove_theme_font_size_override("font_size")
		
		# Force Opaque Background
		var bg_style = StyleBoxFlat.new()
		bg_style.bg_color = Color(0.1, 0.1, 0.1, 1.0) # Dark Opaque Grey
		bg_style.border_width_left = 2
		bg_style.border_width_top = 2
		bg_style.border_width_right = 2
		bg_style.border_width_bottom = 2
		bg_style.border_color = Color.BLACK
		popup.add_theme_stylebox_override("panel", bg_style)
		
		# Add Default Color Preset
		var default_bg = Color(0.0078, 0.0157, 0.0235, 1)
		if not picker.get_presets().has(default_bg):
			picker.add_preset(default_bg)
			
		# Simplify Picker UI
		picker.edit_alpha = false
		picker.can_add_swatches = false
		picker.sampler_visible = false
		picker.color_modes_visible = false
		picker.sliders_visible = false # Hide huge sliders
		picker.hex_visible = true # Keep Hex for precision
		picker.presets_visible = true
	
func _style_option_row(label_btn: Button, toggle: Control, wrapper: Control, font_size: int, scale_factor: float):
	# Style Label Button
	label_btn.add_theme_font_size_override("font_size", font_size)
	
	# Scale Toggle
	toggle.scale = Vector2(scale_factor, scale_factor)
	toggle.text = "" # Ensure no text
	toggle.remove_theme_font_size_override("font_size")
	
	# Calculate toggle natural size
	toggle.custom_minimum_size = Vector2.ZERO
	toggle.size = Vector2.ZERO
	var natural_size = toggle.get_combined_minimum_size()
	toggle.size = natural_size
	
	# Resize Wrapper to fit scaled toggle
	# Use a fixed generous height to ensure centering room, usually 40 is good base
	var wrapper_base_height = max(30.0, natural_size.y)
	
	var reserved_width = 70.0 * scale_factor # generous width
	var reserved_height = wrapper_base_height * scale_factor
	
	wrapper.custom_minimum_size = Vector2(reserved_width, reserved_height)
	
	# Center toggle in wrapper
	var child_scaled_height = natural_size.y * scale_factor
	var y_offset = (reserved_height - child_scaled_height) / 2.0
	toggle.position.y = y_offset

	# Special handling for ColorPickerButton to remove text/icon if any default
	if toggle is ColorPickerButton:
		toggle.text = ""
		toggle.icon = null

func open_menu():
	is_open = true
	edge_handler.mouse_filter = Control.MOUSE_FILTER_IGNORE # Disable edge handler while open
	var tween = create_tween()
	tween.tween_property(panel, "position:x", 0.0, ANIM_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	# Set focus to first item for controller navigation
	%ButtonFavourites.grab_focus()
	
	# Disable game input via streamer
	if PicoVideoStreamer.instance:
		# Only disable input if still open (prevents race with fast toggling)
		if is_open:
			PicoVideoStreamer.instance.set_process_unhandled_input(false)
			PicoVideoStreamer.instance.set_process_input(false)

func close_menu():
	is_open = false
	edge_handler.mouse_filter = Control.MOUSE_FILTER_STOP # Re-enable edge handler
	var tween = create_tween()
	tween.tween_property(panel, "position:x", -panel.size.x, ANIM_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	
	# Release focus
	var focus_owner = get_viewport().gui_get_focus_owner()
	if focus_owner:
		focus_owner.release_focus()

	# Re-enable game input
	if PicoVideoStreamer.instance:
		PicoVideoStreamer.instance.set_process_unhandled_input(true)
		PicoVideoStreamer.instance.set_process_input(true)

func _on_edge_handler_input(event: InputEvent):
	# Disable slide if Favourites Editor is open
	if get_tree().root.has_node("FavouritesEditor"):
		return
		
	if event is InputEventScreenTouch:
		if event.pressed:
			edge_drag_start = event.position
			is_edge_dragging = true
			get_viewport().set_input_as_handled()
		else:
			is_edge_dragging = false
	
	elif event is InputEventScreenDrag:
		if is_edge_dragging:
			if (event.position.x - edge_drag_start.x) > swipe_threshold:
				open_menu()
				is_edge_dragging = false
				get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if not is_open:
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			# Outside tap to close
			if is_open and event.position.x > panel.size.x:
				close_menu()
				get_viewport().set_input_as_handled()
		else:
			if is_dragging:
				if event.position.x > panel.size.x / 3.0:
					open_menu()
				else:
					close_menu()
				is_dragging = false
				get_viewport().set_input_as_handled()
					
	elif event is InputEventScreenDrag:
		if is_dragging:
			var new_x = clamp(event.position.x - panel.size.x, -panel.size.x, 0)
			panel.position.x = new_x
			get_viewport().set_input_as_handled()
			
	elif event is InputEventJoypadButton:
		if event.pressed:
			if event.button_index == JoyButton.JOY_BUTTON_A:
				var focus_owner = get_viewport().gui_get_focus_owner()
				if focus_owner and focus_owner is Button:
					focus_owner.pressed.emit()
					get_viewport().set_input_as_handled()
			elif event.button_index == JoyButton.JOY_BUTTON_B or event.button_index == JoyButton.JOY_BUTTON_LEFT_SHOULDER:
				close_menu()
				get_viewport().set_input_as_handled()
			elif event.button_index == JoyButton.JOY_BUTTON_DPAD_UP:
				_navigate_focus(SIDE_TOP)
				get_viewport().set_input_as_handled()
			elif event.button_index == JoyButton.JOY_BUTTON_DPAD_DOWN:
				_navigate_focus(SIDE_BOTTOM)
				get_viewport().set_input_as_handled()
			elif event.button_index == JoyButton.JOY_BUTTON_DPAD_LEFT:
				_adjust_focused_slider(-1)
				get_viewport().set_input_as_handled()
			elif event.button_index == JoyButton.JOY_BUTTON_DPAD_RIGHT:
				_adjust_focused_slider(1)
				get_viewport().set_input_as_handled()
				
	elif event is InputEventJoypadMotion:
		# Also allow stick navigation/adjustment
		if event.axis == JoyAxis.JOY_AXIS_LEFT_X:
			if abs(event.axis_value) > 0.5:
				# Use a timer or a simple "only trigger once per press" check?
				# For sliders, continuous is better, for nav, discrete.
				# Simple implementation: treat strong values as discrete press for now
				# Real implementation would need a repeat timer.
				pass
		elif event.axis == JoyAxis.JOY_AXIS_LEFT_Y:
			if event.axis_value < -0.5:
				_navigate_focus(SIDE_TOP)
				get_viewport().set_input_as_handled() # Consume to prevent double nav if GODOT handles it
			elif event.axis_value > 0.5:
				_navigate_focus(SIDE_BOTTOM)
				get_viewport().set_input_as_handled()

func _on_select_root_pressed():
	if OS.get_name() == "Android":
		pass
	
	var current_dir = custom_root_path if not custom_root_path.is_empty() else "/sdcard"
	DisplayServer.file_dialog_show("Select Root Folder", current_dir, "", false, DisplayServer.FILE_DIALOG_MODE_OPEN_DIR, [], _on_root_dir_selected)

func _on_root_dir_selected(status: bool, selected_paths: PackedStringArray, _filter_index: int):
	if status and not selected_paths.is_empty():
		var raw_path = selected_paths[0]
		# Sanitize path using BootManager logic
		custom_root_path = PicoBootManager.sanitize_uri(raw_path)
		
		# Extra cleanup for redundancy
		if custom_root_path.begins_with("file://"):
			custom_root_path = custom_root_path.replace("file://", "")
			
		_update_root_path_label()
		save_config() # Auto-save

func _on_clear_root_pressed():
	custom_root_path = ""
	_update_root_path_label()
	save_config()

func _update_root_path_label():
	if %LabelRootPath:
		if custom_root_path.is_empty():
			%LabelRootPath.text = "No custom root path set"
			%LabelRootPath.modulate = Color(0.5, 0.5, 0.5)
			%ButtonClearRoot.visible = false
		else:
			%LabelRootPath.text = custom_root_path
			%LabelRootPath.modulate = Color(0.7, 1.0, 0.7)
			%ButtonClearRoot.visible = true

func _adjust_focused_slider(direction: int):
	var focus_owner = get_viewport().gui_get_focus_owner()
	if focus_owner and focus_owner is HSlider:
		focus_owner.value += focus_owner.step * direction

func _update_audio_label(is_stream: bool):
	if %ButtonAudioBackendLabel:
		%ButtonAudioBackendLabel.text = "TCP Stream" if is_stream else "SLES (Standard)"

func _on_audio_backend_toggled(toggled_on: bool):
	audio_backend = "stream" if toggled_on else "sles"
	_update_audio_label(toggled_on)
	
	# Auto-save immediately so the setting persists for the restart
	# We use a targeted save to avoid committing other unsaved UI changes
	_save_audio_setting_only()
	
	OS.alert("App restart required for audio changes.", "Restart Required")

func _save_audio_setting_only():
	var config = ConfigFile.new()
	# Load existing file to preserve other settings as they are ON DISK
	# ignoring whatever changes are currently pending in the UI
	var err = config.load(CONFIG_PATH)
	if err != OK:
		# If file doesn't exist, we just start fresh, which is fine
		pass
		
	config.set_value("settings", "audio_backend", audio_backend)
	config.save(CONFIG_PATH)

func _navigate_focus(side: Side):
	var current_focus = get_viewport().gui_get_focus_owner()
	if not current_focus:
		%ButtonFavourites.grab_focus()
		return
		
	var neighbor = current_focus.find_valid_focus_neighbor(side)
	if neighbor:
		neighbor.grab_focus()

func _on_haptic_toggled(toggled_on: bool):
	PicoVideoStreamer.set_haptic_enabled(toggled_on)

func _on_swap_zx_toggled(toggled_on: bool):
	PicoVideoStreamer.set_swap_zx_enabled(toggled_on)

func _on_keyboard_toggled(toggled_on: bool):
	# Toggle between Full and Gaming keyboard logic
	KBMan.set_full_keyboard_enabled(toggled_on)
	
	# Refresh Arranger if needed
	var arranger = get_tree().root.get_node_or_null("Main/Arranger")
	if arranger:
		arranger.dirty = true

func _on_label_pressed(button: CheckButton):
	button.button_pressed = not button.button_pressed

func _on_external_keyboard_change(enabled: bool):
	if %ToggleKeyboard:
		%ToggleKeyboard.set_pressed_no_signal(enabled)

func _on_input_mode_toggled(toggled_on: bool):
	PicoVideoStreamer.set_input_mode(toggled_on)
	_update_input_mode_label(toggled_on)

func _update_input_mode_label(is_trackpad: bool):
	if %ButtonInputMode:
		%ButtonInputMode.text = "Input: Trackpad" if is_trackpad else "Input: Mouse"
	
	if %SliderSensitivity:
		%SliderSensitivity.editable = is_trackpad
		%SliderSensitivity.modulate.a = 1.0 if is_trackpad else 0.3
		
	if %LabelSensitivity:
		%LabelSensitivity.modulate.a = 1.0 if is_trackpad else 0.3
		
	if %LabelSensitivityValue:
		%LabelSensitivityValue.modulate.a = 1.0 if is_trackpad else 0.3

func _on_sensitivity_changed(val: float):
	PicoVideoStreamer.set_trackpad_sensitivity(val * 0.5)
	%LabelSensitivityValue.text = str(val)

func _on_saturation_changed(val: float):
	PicoVideoStreamer.set_saturation(val)
	%LabelSaturationValue.text = "%.2f" % val

func _on_saturation_minus():
	var new_val = %SliderSaturation.value - %SliderSaturation.step
	%SliderSaturation.value = clamp(new_val, %SliderSaturation.min_value, %SliderSaturation.max_value)

func _on_saturation_plus():
	var new_val = %SliderSaturation.value + %SliderSaturation.step
	%SliderSaturation.value = clamp(new_val, %SliderSaturation.min_value, %SliderSaturation.max_value)

func _on_button_hue_changed(val: float):
	# Convert 0.0-2.0 range to -180 to +180 degrees
	# 1.0 is neutral (0 degrees)
	var degrees = (val - 1.0) * 180.0
	PicoVideoStreamer.set_button_hue(degrees)
	%LabelButtonHueValue.text = "%.2f" % val

func _on_button_hue_minus():
	var new_val = %SliderButtonHue.value - %SliderButtonHue.step
	%SliderButtonHue.value = clamp(new_val, %SliderButtonHue.min_value, %SliderButtonHue.max_value)

func _on_button_hue_plus():
	var new_val = %SliderButtonHue.value + %SliderButtonHue.step
	%SliderButtonHue.value = clamp(new_val, %SliderButtonHue.min_value, %SliderButtonHue.max_value)

func _on_button_sat_changed(val: float):
	PicoVideoStreamer.set_button_saturation(val)
	%LabelButtonSatValue.text = "%.2f" % val

func _on_button_sat_minus():
	var new_val = %SliderButtonSat.value - %SliderButtonSat.step
	%SliderButtonSat.value = clamp(new_val, %SliderButtonSat.min_value, %SliderButtonSat.max_value)

func _on_button_sat_plus():
	var new_val = %SliderButtonSat.value + %SliderButtonSat.step
	%SliderButtonSat.value = clamp(new_val, %SliderButtonSat.min_value, %SliderButtonSat.max_value)

func _on_button_light_changed(val: float):
	PicoVideoStreamer.set_button_lightness(val)
	%LabelButtonLightValue.text = "%.2f" % val

func _on_button_light_minus():
	var new_val = %SliderButtonLight.value - %SliderButtonLight.step
	%SliderButtonLight.value = clamp(new_val, %SliderButtonLight.min_value, %SliderButtonLight.max_value)

func _on_button_light_plus():
	var new_val = %SliderButtonLight.value + %SliderButtonLight.step
	%SliderButtonLight.value = clamp(new_val, %SliderButtonLight.min_value, %SliderButtonLight.max_value)

func _on_integer_scaling_toggled(toggled_on: bool):
	PicoVideoStreamer.set_integer_scaling_enabled(toggled_on)
	# Force Arranger update
	var arranger = get_tree().root.get_node_or_null("Main/Arranger")
	if arranger:
		arranger.dirty = true

func _on_show_controls_toggled(toggled_on: bool):
	PicoVideoStreamer.set_always_show_controls(toggled_on)
	# Force Arranger update
	var arranger = get_tree().root.get_node_or_null("Main/Arranger")
	if arranger:
		arranger.dirty = true

func _on_bezel_toggled(toggled_on: bool):
	PicoVideoStreamer.set_bezel_enabled(toggled_on)

func _on_reposition_toggled(toggled_on: bool):
	PicoVideoStreamer.set_display_drag_enabled(toggled_on)

func _style_shader_select_row(label_btn: Button, option_btn: OptionButton, wrapper: Control, font_size: int, scale_factor: float):
	# Style Label Button
	label_btn.add_theme_font_size_override("font_size", font_size)
	
	# Style OptionButton - smaller font and scale for the selected text display
	option_btn.add_theme_font_size_override("font_size", int(font_size * 0.5))
	option_btn.scale = Vector2(scale_factor * 0.6, scale_factor * 0.6)
	
	# Calculate natural size
	option_btn.custom_minimum_size = Vector2.ZERO
	var natural_size = option_btn.get_combined_minimum_size()
	
	# Resize Wrapper
	var wrapper_base_height = max(30.0, natural_size.y)
	var reserved_width = 120.0 * scale_factor
	var reserved_height = wrapper_base_height * scale_factor * 0.6
	
	wrapper.custom_minimum_size = Vector2(reserved_width, reserved_height)
	
	# Center option button in wrapper
	var child_scaled_height = natural_size.y * scale_factor * 0.6
	var y_offset = (reserved_height - child_scaled_height) / 2.0
	option_btn.position.y = y_offset

func _on_shader_button_pressed():
	# Cycle through shader options
	var current = %ShaderSelect.selected
	%ShaderSelect.select((current + 1) % %ShaderSelect.item_count)
	_on_shader_selected(%ShaderSelect.selected)

func _on_shader_selected(index: int):
	PicoVideoStreamer.set_shader_type(index as PicoVideoStreamer.ShaderType)

var connected_controllers_dialog_instance = null

func _on_connected_controllers_pressed():
	if is_instance_valid(connected_controllers_dialog_instance):
		return
		
	var dialog = connected_controllers_dialog_scene.instantiate()
	get_tree().root.add_child(dialog)
	connected_controllers_dialog_instance = dialog
	
	close_menu()
	
	# Scale Dialog (rough approximation based on current UI scale)
	# We need to fetch the calculated scale_factor from _update_layout. 
	# Or recalculate it. Let's recalculate cleanly.
	var viewport_size = get_viewport().get_visible_rect().size
	var min_dim = min(viewport_size.x, viewport_size.y)
	var dynamic_font_size = int(max(24, min_dim * 0.04))
	var scale_factor = float(dynamic_font_size) / 10.0
	scale_factor = clamp(scale_factor, 1.2, 3.0)
	
	if dialog.has_method("set_scale_factor"):
		dialog.set_scale_factor(scale_factor)
		
	# Center it
	dialog.position = (viewport_size - dialog.size * scale_factor) / 2.0

func _on_bg_color_picked(color: Color):
	RenderingServer.set_default_clear_color(color)

func save_config():
	var config = ConfigFile.new()
	config.set_value("settings", "haptic_enabled", PicoVideoStreamer.get_haptic_enabled())
	config.set_value("settings", "swap_zx_enabled", PicoVideoStreamer.get_swap_zx_enabled())
	config.set_value("settings", "trackpad_sensitivity", PicoVideoStreamer.get_trackpad_sensitivity())
	config.set_value("settings", "integer_scaling_enabled", PicoVideoStreamer.get_integer_scaling_enabled())
	config.set_value("settings", "bezel_enabled", PicoVideoStreamer.get_bezel_enabled())
	config.set_value("settings", "always_show_controls", PicoVideoStreamer.get_always_show_controls())
	config.set_value("settings", "ignored_devices_by_user", ControllerUtils.ignored_devices_by_user)
	config.set_value("settings", "controller_assignments", ControllerUtils.controller_assignments)
	config.set_value("settings", "shader_type", PicoVideoStreamer.get_shader_type())
	config.set_value("settings", "saturation", PicoVideoStreamer.get_saturation())
	config.set_value("settings", "button_hue", PicoVideoStreamer.get_button_hue())
	config.set_value("settings", "button_saturation", PicoVideoStreamer.get_button_saturation())
	config.set_value("settings", "button_lightness", PicoVideoStreamer.get_button_lightness())
	config.set_value("settings", "bg_color", %ColorPickerBG.color)
	config.set_value("settings", "display_drag_offset_portrait", PicoVideoStreamer.display_drag_offset_portrait)
	config.set_value("settings", "display_drag_offset_landscape", PicoVideoStreamer.display_drag_offset_landscape)
	config.set_value("settings", "display_scale_portrait", PicoVideoStreamer.display_scale_portrait)
	config.set_value("settings", "display_scale_landscape", PicoVideoStreamer.display_scale_landscape)
	config.set_value("settings", "audio_backend", audio_backend)
	config.set_value("settings", "custom_root_path", custom_root_path)
	config.set_value("settings", "control_layout_portrait", PicoVideoStreamer.control_layout_portrait)
	config.set_value("settings", "control_layout_landscape", PicoVideoStreamer.control_layout_landscape)
	config.save(CONFIG_PATH)
	
	# Visual Feedback
	var orig_text = %ButtonSave.text
	%ButtonSave.text = "   Saved!"
	%ButtonSave.release_focus() # Optional style choice, but keeps it clean
	%ButtonSave.grab_focus() # Restore focus so nav isn't lost
	
	await get_tree().create_timer(1.0).timeout
	%ButtonSave.text = orig_text
	
func load_config():
	var config = ConfigFile.new()
	var err = config.load(CONFIG_PATH)
	
	var haptic = false
	var swap_zx = false
	var sensitivity = 0.5
	var integer_scaling = true
	var bezel = false
	var always_show = false
	var shader_type = PicoVideoStreamer.ShaderType.NONE
	var saturation = 1.0
	var button_hue = 0.0
	var button_saturation = 1.0
	var button_lightness = 1.0
	var display_drag_enabled = false
	var display_drag_offset_portrait = Vector2.ZERO
	var display_drag_offset_landscape = Vector2.ZERO
	var display_scale_portrait = 1.0
	var display_scale_landscape = 1.0
	var control_layout_portrait = {}
	var control_layout_landscape = {}
	var audio_backend_loaded = "sles"
	var custom_root_path_loaded = ""
	
	if err == OK:
		haptic = config.get_value("settings", "haptic_enabled", false)
		swap_zx = config.get_value("settings", "swap_zx_enabled", false)
		sensitivity = config.get_value("settings", "trackpad_sensitivity", 0.5)
		integer_scaling = config.get_value("settings", "integer_scaling_enabled", true)
		bezel = config.get_value("settings", "bezel_enabled", false)
		always_show = config.get_value("settings", "always_show_controls", false)
		# Safely load typed array for ignored devices
		var loaded_ignored = config.get_value("settings", "ignored_devices_by_user", [])
		ControllerUtils.ignored_devices_by_user.clear()
		for device in loaded_ignored:
			ControllerUtils.ignored_devices_by_user.append(str(device))
		
		# ControllerUtils.ignored_devices_by_user = config.get_value("settings", "ignored_devices_by_user", [])
		ControllerUtils.controller_assignments = config.get_value("settings", "controller_assignments", {})
		
		# Load shader type (defaults to NONE if not saved)
		shader_type = config.get_value("settings", "shader_type", PicoVideoStreamer.ShaderType.NONE)
		
		# Load saturation
		saturation = config.get_value("settings", "saturation", 1.0)
		
		# Load button hue
		button_hue = config.get_value("settings", "button_hue", 0.0)
		
		# Load button saturation and lightness
		button_saturation = config.get_value("settings", "button_saturation", 1.0)
		button_lightness = config.get_value("settings", "button_lightness", 1.0)
		
		# Load reposition settings
		display_drag_offset_portrait = config.get_value("settings", "display_drag_offset_portrait", Vector2.ZERO)
		display_drag_offset_landscape = config.get_value("settings", "display_drag_offset_landscape", Vector2.ZERO)
		display_scale_portrait = config.get_value("settings", "display_scale_portrait", 1.0)
		display_scale_landscape = config.get_value("settings", "display_scale_landscape", 1.0)
		
		control_layout_portrait = config.get_value("settings", "control_layout_portrait", {})
		control_layout_landscape = config.get_value("settings", "control_layout_landscape", {})
		
		# Legacy migration (if single offset existed, apply to both or just portrait? let's stick to default)
		if config.has_section_key("settings", "display_drag_offset"):
			var legacy_offset = config.get_value("settings", "display_drag_offset", Vector2.ZERO)
			# Only apply if new ones are zero
			if display_drag_offset_portrait == Vector2.ZERO:
				display_drag_offset_portrait = legacy_offset
			if display_drag_offset_landscape == Vector2.ZERO:
				display_drag_offset_landscape = legacy_offset
		
		# Safely load typed array
		var saved_ignored = config.get_value("settings", "ignored_devices_by_user", [])
		ControllerUtils.ignored_devices_by_user.clear()
		for device in saved_ignored:
			ControllerUtils.ignored_devices_by_user.append(str(device))
		
		# Migration: Check for old oled_mode first
		var default_bg = Color(0.0078, 0.0157, 0.0235, 1)
		var saved_bg = config.get_value("settings", "bg_color", null)
		
		if saved_bg == null:
			# Check for legacy OLED setting
			if config.has_section_key("settings", "oled_mode"):
				var oled_active = config.get_value("settings", "oled_mode", false)
				saved_bg = Color.BLACK if oled_active else default_bg
			else:
				saved_bg = default_bg
		
		# Apply BG Color
		if %ColorPickerBG:
			%ColorPickerBG.color = saved_bg
			_on_bg_color_picked(saved_bg)
			
		# Load Audio Backend
		audio_backend_loaded = config.get_value("settings", "audio_backend", "sles")
		custom_root_path_loaded = config.get_value("settings", "custom_root_path", "")
	
	# Apply Settings
	custom_root_path = custom_root_path_loaded
	_update_root_path_label()
	
	audio_backend = audio_backend_loaded
	if %ToggleAudioBackend:
		var is_stream = (audio_backend == "stream")
		%ToggleAudioBackend.set_pressed_no_signal(is_stream)
		_update_audio_label(is_stream)
	
	PicoVideoStreamer.set_haptic_enabled(haptic)
	PicoVideoStreamer.set_swap_zx_enabled(swap_zx)
	PicoVideoStreamer.set_trackpad_sensitivity(sensitivity)
	PicoVideoStreamer.set_integer_scaling_enabled(integer_scaling)
	PicoVideoStreamer.set_bezel_enabled(bezel)
	PicoVideoStreamer.set_always_show_controls(always_show)
	PicoVideoStreamer.set_shader_type(shader_type)
	PicoVideoStreamer.set_saturation(saturation)
	PicoVideoStreamer.set_button_hue(button_hue)
	PicoVideoStreamer.set_button_saturation(button_saturation)
	PicoVideoStreamer.set_button_lightness(button_lightness)
	PicoVideoStreamer.set_display_drag_offset(display_drag_offset_portrait, false)
	PicoVideoStreamer.set_display_drag_offset(display_drag_offset_landscape, true)
	PicoVideoStreamer.set_display_scale_modifier(display_scale_portrait, false)
	PicoVideoStreamer.set_display_scale_modifier(display_scale_landscape, true)
	
	PicoVideoStreamer.control_layout_portrait = control_layout_portrait
	PicoVideoStreamer.control_layout_landscape = control_layout_landscape
	
	# Update UI
	if %ToggleHaptic: %ToggleHaptic.set_pressed_no_signal(haptic)
	if %ToggleSwapZX: %ToggleSwapZX.set_pressed_no_signal(swap_zx)
	if %ToggleIntegerScaling: %ToggleIntegerScaling.set_pressed_no_signal(integer_scaling)
	if %ToggleBezel: %ToggleBezel.set_pressed_no_signal(bezel)
	if %ToggleReposition: %ToggleReposition.set_pressed_no_signal(display_drag_enabled)
	if %ToggleShowControls: %ToggleShowControls.set_pressed_no_signal(always_show)
	if %ShaderSelect: %ShaderSelect.select(shader_type)
	if %SliderSensitivity:
		%SliderSensitivity.set_value_no_signal(sensitivity) # avoid double setting
		%LabelSensitivityValue.text = str(sensitivity)
	if %SliderSaturation:
		%SliderSaturation.set_value_no_signal(saturation)
		%LabelSaturationValue.text = "%.2f" % saturation
	if %SliderButtonHue:
		# Convert degrees (-180 to 180) back to slider range (0.0 to 2.0)
		var slider_val = (button_hue / 180.0) + 1.0
		%SliderButtonHue.set_value_no_signal(slider_val)
		%LabelButtonHueValue.text = "%.2f" % slider_val
	if %SliderButtonSat:
		%SliderButtonSat.set_value_no_signal(button_saturation)
		%LabelButtonSatValue.text = "%.2f" % button_saturation
	if %SliderButtonLight:
		%SliderButtonLight.set_value_no_signal(button_lightness)
		%LabelButtonLightValue.text = "%.2f" % button_lightness
		
	# Sync other non-saved states usually comes from default checks
	if %ToggleInputMode:
		# Default to whatever PicoVideoStreamer has (usually MOUSE default)
		var is_trackpad = PicoVideoStreamer.get_input_mode() == PicoVideoStreamer.InputMode.TRACKPAD
		%ToggleInputMode.set_pressed_no_signal(is_trackpad)
		_update_input_mode_label(is_trackpad)

	if %ToggleKeyboard:
		%ToggleKeyboard.button_pressed = KBMan.get_current_keyboard_type() == KBMan.KBType.FULL

func _on_app_settings_pressed():
	if Applinks:
		Applinks.open_app_settings()

func _on_support_pressed():
	OS.shell_open("https://ko-fi.com/macs34661")

func _on_section_toggled(btn: Button, container: Control):
	var should_be_visible = !container.visible
	container.visible = should_be_visible
	btn.text = ("🔽" if should_be_visible else "▶️ ") + btn.text.substr(2)
	
	# Animate? Simple toggle is robust for now.
	# If invisible, it shrinks automatically due to VBoxContainer.

func _on_favourites_pressed():
	# Check if already open
	if has_node("/root/FavouritesEditor"):
		return
		
	# Disable Layout Customization if active
	if PicoVideoStreamer.display_drag_enabled:
		PicoVideoStreamer.set_display_drag_enabled(false)
		if %ToggleReposition:
			%ToggleReposition.set_pressed_no_signal(false)
			
	var editor = favourites_editor_scene.instantiate()
	get_tree().root.add_child(editor)
	
	# Close options menu to give space
	close_menu()

func _on_play_stats_pressed():
	var editor = favourites_editor_scene.instantiate()
	# Set mode to STATS (Enum value 1)
	editor.current_mode = 1 # EditorMode.STATS
	get_tree().root.add_child(editor)
	
	close_menu()
