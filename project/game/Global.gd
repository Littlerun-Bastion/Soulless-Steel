extends Node

const ANTI_ALIASING_OFF := 0
const ANTI_ALIASING_LOW := 1
const ANTI_ALIASING_HIGH := 2
const ANTI_ALIASING_NAMES := ["OFF", "LOW", "HIGH"]

var previous_windowed_pos = false
# Automated tests set this so loading a test profile doesn't resize the window.
var keep_window := false

## Off draws textures as the project always has (Nearest). Low smooths them,
## through their mipmaps as the camera pulls back; High also puts 4x MSAA on
## edges and lines. Only the game's own viewport: the HUD draws in a viewport
## of its own and is left as it is.
func apply_anti_aliasing() -> void:
	var level: int = Profile.get_option("anti_aliasing")
	var root := get_tree().root
	var smooth := level != ANTI_ALIASING_OFF
	root.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if smooth \
			else Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.msaa_2d = Viewport.MSAA_4X if level == ANTI_ALIASING_HIGH else Viewport.MSAA_DISABLED


func toggle_fullscreen():
	var window = get_window()
	if window.mode == Window.MODE_WINDOWED:
		previous_windowed_pos = window.position
	Profile.set_option("fullscreen", window.mode == Window.MODE_WINDOWED, true)
	apply_window_mode()


# Puts the window in the mode saved in the profile options (fullscreen, or a
# window of the chosen size). Called when the profile loads and on F11.
func apply_window_mode():
	if keep_window:
		return
	var window = get_window()
	var cur_screen = window.get_current_screen()
	var fullscreen: bool = Profile.get_option("fullscreen")
	window.mode = Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED
	window.borderless = fullscreen
	if not fullscreen:
		var size = Profile.WINDOW_SIZES[int(Profile.get_option("window_size"))]
		window.size = size
		if previous_windowed_pos:
			window.position = previous_windowed_pos
		else:
			window.move_to_center()
		window.set_current_screen(cur_screen)
