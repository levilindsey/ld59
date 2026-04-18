class_name DebugConsole
extends PanelContainer


@export var font_color := Color("c5ff5e")
@export var message_count_limit := 500

var text := ""
var _message_count := 0


func _enter_tree() -> void:
	visible = G.settings.show_debug_console


func _ready() -> void:
	_log_print_queue()
	G.log.is_queuing_messages = false
	G.log.on_message.connect(add_message)

	%ConcatenatedLogs.add_theme_color_override("font_color", font_color)
	%Time.add_theme_color_override("font_color", font_color)

	G.time.set_timeout(_delayed_init, 0.8)


func _process(_delta: float) -> void:
	%Time.text = Utils.get_time_string_from_seconds(
			G.time.get_app_time(),
			false,
			false,
			true) + " "


func _delayed_init() -> void:
	if not G.settings.show_debug_console:
		return

	_set_concatenated_logs(text)


func add_message(message: String) -> void:
	if not G.settings.show_debug_console:
		return

	text += "> " + message + "\n"
	_message_count += 1
	_remove_surplus_message()
	_set_concatenated_logs(text)


func _set_concatenated_logs(p_text: String) -> void:
	text = p_text
	if not is_node_ready():
		return
	%ConcatenatedLogs.text = text
	G.time.set_timeout(_scroll_to_bottom, 0.2)


func _remove_surplus_message() -> void:
	# Remove the oldest message.
	if _message_count > message_count_limit:
		var index := text.find("\n> ")
		text = text.substr(index + 1)


func _scroll_to_bottom() -> void:
	%ScrollContainer.scroll_vertical = \
			%ScrollContainer.get_v_scroll_bar().max_value


func _log_print_queue() -> void:
	if not G.settings.show_debug_console:
		return

	for entry in G.log._print_queue:
		add_message(entry)
	G.log._print_queue.clear()
