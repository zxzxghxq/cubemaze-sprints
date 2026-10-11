extends CanvasLayer

const MAIN_LEVEL_PATH: String = "res://scenes/mainscience.tscn"
const LEVEL_1_PATH: String = "res://level1.tscn"
const LEVEL_2_PATH: String = "res://level2.tscn"

@onready var menu_root: Control = $MenuRoot
@onready var resume_button: Button = $MenuRoot/Center/Panel/Margin/Buttons/ResumeButton

var _menu_open: bool = false
var _mouse_mode_before_menu: Input.MouseMode = Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	menu_root.visible = false

	resume_button.pressed.connect(_close_menu)
	$MenuRoot/Center/Panel/Margin/Buttons/MainLevelButton.pressed.connect(
		_change_level.bind(MAIN_LEVEL_PATH)
	)
	$MenuRoot/Center/Panel/Margin/Buttons/Level1Button.pressed.connect(
		_change_level.bind(LEVEL_1_PATH)
	)
	$MenuRoot/Center/Panel/Margin/Buttons/Level2Button.pressed.connect(
		_change_level.bind(LEVEL_2_PATH)
	)
	$MenuRoot/Center/Panel/Margin/Buttons/Level3Button.visible = false
	$MenuRoot/Center/Panel/Margin/Buttons/QuitButton.pressed.connect(_quit_game)


func _input(event: InputEvent) -> void:
	if (
		event is InputEventKey
		and event.keycode == KEY_ESCAPE
		and event.pressed
		and not event.echo
	):
		if _menu_open:
			_close_menu()
		else:
			_open_menu()
		get_viewport().set_input_as_handled()


func _open_menu() -> void:
	_menu_open = true
	_mouse_mode_before_menu = Input.mouse_mode
	menu_root.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	resume_button.grab_focus()


func _close_menu() -> void:
	_menu_open = false
	menu_root.visible = false
	get_tree().paused = false
	Input.mouse_mode = _mouse_mode_before_menu


func _change_level(scene_path: String) -> void:
	_menu_open = false
	menu_root.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var change_error := get_tree().change_scene_to_file(scene_path)
	if change_error != OK:
		push_error("Unable to switch to scene %s. Error code: %s" % [scene_path, change_error])


func _quit_game() -> void:
	get_tree().paused = false
	get_tree().quit()
