extends Control

# Default game server port. Can be any number between 1024 and 49151.
# Not present on the list of registered or common ports as of May 2024:
# https://en.wikipedia.org/wiki/List_of_TCP_and_UDP_port_numbers
const DEFAULT_PORT = 8910

@onready var address: LineEdit = $Address
@onready var host_button: Button = $HostButton
@onready var join_button: Button = $JoinButton
@onready var match_button: Button = $MatchButton
@onready var status_ok: Label = $StatusOk
@onready var status_fail: Label = $StatusFail
@onready var port_forward_label: Label = $PortForward
@onready var find_public_ip_button: LinkButton = $FindPublicIP

var peer: ENetMultiplayerPeer

func _is_dedicated_server() -> bool:
	return OS.has_feature("dedicated_server") || Ams.is_enabled()

func _ready() -> void:
	# Connect all the callbacks related to networking.
	multiplayer.peer_connected.connect(_player_connected)
	multiplayer.peer_disconnected.connect(_player_disconnected)
	multiplayer.connected_to_server.connect(_connected_ok)
	multiplayer.connection_failed.connect(_connected_fail)
	multiplayer.server_disconnected.connect(_server_disconnected)
	
	if _is_dedicated_server():
		# Run your server startup code here...
		_host_server()
		if (Ams.is_enabled()):
			Ams.SendReady()

#region Network callbacks from SceneTree
# Callback from SceneTree.
func _player_connected(_id: int) -> void:
	if (multiplayer.get_peers().size() == 2):
		# Everyone connected, start the game!
		var pong: Node2D = load("res://pong.tscn").instantiate()
		# Connect deferred so we can safely erase it from the callback.
		pong.game_finished.connect(_end_game, CONNECT_DEFERRED)

		get_tree().get_root().add_child(pong)
		hide()


func _player_disconnected(_id: int) -> void:
	if multiplayer.is_server():
		_end_game("Client disconnected.")
	else:
		_end_game("Server disconnected.")


# Callback from SceneTree, only for clients (not server).
func _connected_ok() -> void:
	pass # This function is not needed for this project.


# Callback from SceneTree, only for clients (not server).
func _connected_fail() -> void:
	_set_status("Couldn't connect.", false)

	multiplayer.set_multiplayer_peer(null)  # Remove peer.
	_enable_buttons()

func _server_disconnected() -> void:
	_end_game("Server disconnected.")
#endregion

#region Game creation methods
func _end_game(with_error: String = "") -> void:
	if has_node("/root/Pong"):
		# Erase immediately, otherwise network might show
		# errors (this is why we connected deferred above).
		get_node(^"/root/Pong").free()
		show()

	multiplayer.set_multiplayer_peer(null)  # Remove peer.
	_enable_buttons()

	_set_status(with_error, false)
	if _is_dedicated_server():
		get_tree().quit(0)


func _set_status(text: String, is_ok: bool) -> void:
	# Simple way to show status.
	if is_ok:
		status_ok.set_text(text)
		status_fail.set_text("")
	else:
		status_ok.set_text("")
		status_fail.set_text(text)


func _on_host_pressed() -> void:
	_host_server()

func _host_server() -> void:
	peer = ENetMultiplayerPeer.new()
	
	var port := DEFAULT_PORT
	if Ams.is_enabled() && Ams.port != 0:
		port = Ams.port
	var err := peer.create_server(port, 2)
	if err != OK:
		# Is another server running?
		_set_status("Can't host, address in use.",false)
		return
	peer.get_host().compress(ENetConnection.COMPRESS_RANGE_CODER)

	multiplayer.set_multiplayer_peer(peer)
	_disable_buttons()
	_set_status("Waiting for player...", true)
	get_window().title = ProjectSettings.get_setting("application/config/name") + ": Server"

	# Only show hosting instructions when relevant.
	port_forward_label.visible = true
	find_public_ip_button.visible = true

func _disable_buttons() -> void:
	host_button.set_disabled(true)
	join_button.set_disabled(true)
	match_button.set_disabled(true)
	
func _enable_buttons() -> void:
	host_button.set_disabled(false)
	join_button.set_disabled(false)
	match_button.set_disabled(false)
var socket := WebSocketPeer.new()
func _process(_delta: float) -> void:
	socket.poll()
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		while socket.get_available_packet_count():
			var message := socket.get_packet().get_string_from_ascii()
			var ip_port := message.split(":")
			if len(ip_port) == 2 && ip_port[0].is_valid_ip_address() && ip_port[1].is_valid_int():
				_set_status("connecting to server at " + message, true)
				_join_game(ip_port[0], ip_port[1].to_int())
			else:
				_set_status(message, true)

func _on_match_pressed() -> void:
	_set_status("", true)
	var ip_port := address.get_text().split(":")
	var ip := ip_port[0]
	if not ip.is_valid_ip_address():
		_set_status("IP address is invalid.", false)
		return
	var matchmaker_address := "ws://"+ip
	if ip_port.size()>1:
		matchmaker_address = matchmaker_address + ":" + ip_port[1]
	
	var socket_state := socket.get_ready_state()
	if socket_state == WebSocketPeer.STATE_CLOSED || socket_state == WebSocketPeer.STATE_CLOSING:
		if socket.connect_to_url(matchmaker_address) != OK:
			_set_status("Unable to connect to matchmaker.", false)
			set_process(false)
		_set_status("Matchmaking...", true)
	
	_disable_buttons()
	while socket.get_ready_state() == WebSocketPeer.STATE_CONNECTING:
		# Create a Timer node
		var timer := Timer.new()
		add_child(timer)
		timer.wait_time = 0.2
		timer.start()
		await timer.timeout
		remove_child(timer)

func _on_join_pressed() -> void:
	var ip_port := address.get_text().split(":")
	var ip := ip_port[0]
	if not ip.is_valid_ip_address():
		_set_status("IP address is invalid.", false)
		return
	
	var port := DEFAULT_PORT
	if ip_port.size()>1 && ip_port[1].is_valid_int():
		port = ip_port[1].to_int()
	_join_game(ip, port)

func _join_game(ip: String, port: int) -> void:
	peer = ENetMultiplayerPeer.new()
	peer.create_client(ip, port)
	peer.get_host().compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.set_multiplayer_peer(peer)
	_disable_buttons()
	_set_status("Connecting to %s:%d "%[ip, port], true)
	get_window().title = ProjectSettings.get_setting("application/config/name") + ": Client"
#endregion

func _on_find_public_ip_pressed() -> void:
	OS.shell_open("https://icanhazip.com/")
