extends Node

# The URL we will connect to.
var watchdog_websocket_url = "ws://localhost:5555/watchdog"
var socket := WebSocketPeer.new()
var heartbeat_timer := Timer.new()

signal drain

var dsid
var port

func is_enabled():
	return dsid != null

func _parse_cmdline_user_args():
	var arguments = {}
	var cmd_args = OS.get_cmdline_args()
	for argument in cmd_args:
		# Parse valid command-line arguments into a dictionary
		if argument.find("=") > -1:
			var key_value = argument.split("=")
			arguments[key_value[0].lstrip("--")] = key_value[1]
	return arguments

func _ready():	
	var args = _parse_cmdline_user_args()
	if args.has("dsid"):
		dsid = args["dsid"]
	if args.has("port"):
		port = args["port"]
	
	if dsid == null:
		return 
	
	heartbeat_timer.timeout.connect(_send_heartbeat)
	add_child(heartbeat_timer)
	heartbeat_timer.start(15)
	
	_connect()

func _process(_delta):
	socket.poll()

	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		while socket.get_available_packet_count():
			_parse_message(socket.get_packet().get_string_from_ascii())

func _parse_message(message):
	var data = JSON.parse_string(message)
	if data == null:
		push_error("failed to parse")
		return
	else:
		if typeof(data) == TYPE_DICTIONARY:
			if data.has("drain"):
				drain.emit()
			else:
				push_warning("unhandled message from watchdog", message)
		else:
			push_error("unexpected message", message)

func _connect():
	if socket.connect_to_url(watchdog_websocket_url) != OK:
		push_error("Unable to connect.")
		set_process(false)	

func _exit_tree():
	socket.close()

func _send_heartbeat():
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		_connect()
	
	var message = JSON.stringify({
	"heartbeat": {},
	})
	socket.send_text(message)

func SendReady():
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		_connect()
	var message = JSON.stringify({
		"ready": {
			"dsid": dsid
		},
	})
	socket.send_text(message)
