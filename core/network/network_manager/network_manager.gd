extends CanvasLayer

const lobby_room_name: String = "lobby"
const experience_room_prefix: String = "experience_"
const DEBUG_MASTER_HANDOFF := true
const HANDOFF_HEARTBEAT_INTERVAL := 2.0
const HANDOFF_HEARTBEAT_TIMEOUT := 4.0
const HANDOFF_RETRY_INTERVAL_MSEC := 1000
const HANDOFF_PROPERTY_PREFIX := "handoff_active_"

var _pending_room_name: String
var _register_current_scene_after_join := false
var _is_local_handoff_active := true
var _next_handoff_retry_msec := 0
var _next_stale_master_check_msec := 0
var _handoff_heartbeat_timer: Timer
var _web_focus_callback: JavaScriptObject
var _web_blur_callback: JavaScriptObject
var _web_page_show_callback: JavaScriptObject
var _web_page_hide_callback: JavaScriptObject
var _web_visibility_change_callback: JavaScriptObject


func _ready() -> void:
	Fusion.connected_to_photon.connect(_on_connected_to_photon)
	Fusion.room_left.connect(_on_room_left)
	Fusion.room_joined.connect(_on_room_joined)
	Fusion.player_left.connect(_on_player_left)
	if Fusion.has_signal(&"player_joined"):
		Fusion.connect(&"player_joined", Callable(self, "_on_player_joined"))
	_start_handoff_heartbeat_timer()
	_connect_web_lifecycle_events()
	connect_to_lobby.call_deferred()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_OUT:
			if OS.has_feature("web"):
				_update_web_handoff_active("godot focus out %s" % what)
				_debug_master_handoff("web focus-out ignored: notification=%s state={%s}" % [what, _get_network_debug_state()])
				return
			_set_local_handoff_active(false, "godot notification %s" % what)
			_try_handoff_master_client("godot notification %s" % what)
		NOTIFICATION_APPLICATION_PAUSED:
			if OS.has_feature("web"):
				_update_web_handoff_active("godot paused %s" % what)
				if not _is_local_handoff_active:
					_try_handoff_master_client("godot paused %s" % what)
				else:
					_debug_master_handoff("web pause ignored while visible: notification=%s state={%s}" % [what, _get_network_debug_state()])
				return
			_set_local_handoff_active(false, "godot notification %s" % what)
			_try_handoff_master_client("godot notification %s" % what)
		NOTIFICATION_WM_WINDOW_FOCUS_IN, NOTIFICATION_APPLICATION_FOCUS_IN:
			if OS.has_feature("web"):
				_update_web_handoff_active("godot focus in %s" % what)
				_debug_master_handoff("web focus-in observed: notification=%s state={%s}" % [what, _get_network_debug_state()])
				return
			_set_local_handoff_active(true, "godot notification %s" % what)
		NOTIFICATION_APPLICATION_RESUMED:
			if OS.has_feature("web"):
				_update_web_handoff_active("godot resumed %s" % what)
				_debug_master_handoff("web resume observed: notification=%s state={%s}" % [what, _get_network_debug_state()])
				return
			_set_local_handoff_active(true, "godot notification %s" % what)


func _process(__: float) -> void:
	_update_web_handoff_active("process")
	_retry_inactive_master_handoff()
	_try_takeover_stale_master_client()


func _retry_inactive_master_handoff() -> void:
	if _is_local_handoff_active:
		return
	if not Fusion.is_master_client():
		return
	if not Fusion.is_in_room():
		return
	if not OS.has_feature("web"):
		return

	var now := Time.get_ticks_msec()
	if now < _next_handoff_retry_msec:
		return

	_next_handoff_retry_msec = now + HANDOFF_RETRY_INTERVAL_MSEC
	_debug_master_handoff("inactive master retry: state={%s}" % _get_network_debug_state())
	_handoff_master_client()


func _try_takeover_stale_master_client() -> void:
	if not _is_local_handoff_active:
		return
	if Fusion.is_master_client():
		return
	if not Fusion.is_in_room():
		return

	var now := Time.get_ticks_msec()
	if now < _next_stale_master_check_msec:
		return

	_next_stale_master_check_msec = now + HANDOFF_RETRY_INTERVAL_MSEC
	var room: FusionRoom = Fusion.get_room()
	var local_player_id := Fusion.get_local_player_id()
	var master_player_id := room.get_master_client_id()
	if local_player_id <= 0 or master_player_id <= 0 or master_player_id == local_player_id:
		return

	var room_properties := room.get_custom_properties()
	if _is_handoff_eligible_player(master_player_id, room_properties):
		return

	var next_player_id := _get_handoff_candidate_id(room, master_player_id)
	if next_player_id != local_player_id:
		_debug_master_handoff(
			"stale master takeover skipped: local=%s selected=%s master=%s state={%s}" % [
				local_player_id,
				next_player_id,
				master_player_id,
				_get_network_debug_state(),
			]
		)
		return

	_debug_master_handoff(
		"stale master takeover: master=%s -> local=%s state={%s}" % [
			master_player_id,
			local_player_id,
			_get_network_debug_state(),
		]
	)
	room.set_master_client(local_player_id)


func connect_to_lobby() -> void:
	join_lobby_room()
	Fusion.connect_to_photon()


func join_lobby_room() -> void:
	_join_room(lobby_room_name, false)


func join_experience_room(experience_name: String) -> void:
	_join_room(experience_room_prefix + experience_name, true)


func _join_room(room_name: String, register_current_scene_after_join: bool) -> void:
	_debug_master_handoff(
		"join requested: target=%s register_scene=%s state={%s}" % [
			room_name,
			register_current_scene_after_join,
			_get_network_debug_state(),
		]
	)

	_pending_room_name = room_name
	_register_current_scene_after_join = register_current_scene_after_join

	if not Fusion.is_connected_to_photon():
		return
	if Fusion.is_in_room():
		Fusion.leave_room()
		return

	_join_pending_room()


func _join_pending_room() -> void:
	if _pending_room_name.is_empty():
		_debug_master_handoff("join pending skipped: no pending room state={%s}" % _get_network_debug_state())
		return

	_debug_master_handoff("joining pending room: %s state={%s}" % [_pending_room_name, _get_network_debug_state()])
	Fusion.join_or_create_room(_pending_room_name)


func _on_connected_to_photon() -> void:
	_debug_master_handoff("connected to photon: state={%s}" % _get_network_debug_state())
	if _pending_room_name.is_empty():
		join_lobby_room()
		return

	_join_pending_room()


func _on_room_left() -> void:
	_debug_master_handoff("room left: state={%s}" % _get_network_debug_state())
	_join_pending_room()


func _on_room_joined() -> void:
	_pending_room_name = ""
	_debug_master_handoff("room joined: state={%s}" % _get_network_debug_state())
	_publish_handoff_heartbeat("room joined")
	if _register_current_scene_after_join:
		register_current_scene.call_deferred()


func _on_player_joined(player_id: int, user_id: String) -> void:
	_debug_master_handoff(
		"player joined: player=%s user=%s state={%s}" % [
			player_id,
			user_id,
			_get_network_debug_state(),
		]
	)


func _on_player_left(player_id: int, is_inactive: bool) -> void:
	_debug_master_handoff(
		"player left: player=%s inactive=%s state={%s}" % [
			player_id,
			is_inactive,
			_get_network_debug_state(),
		]
	)


func register_current_scene() -> void:
	if not Fusion.is_in_room():
		return
	if get_tree().current_scene == null:
		return

	Fusion.register_current_scene()


func _connect_web_lifecycle_events() -> void:
	if not OS.has_feature("web"):
		return

	var window: JavaScriptObject = JavaScriptBridge.get_interface("window")
	var document: JavaScriptObject = JavaScriptBridge.get_interface("document")

	_web_focus_callback = JavaScriptBridge.create_callback(_on_web_focus)
	_web_blur_callback = JavaScriptBridge.create_callback(_on_web_blur)
	_web_page_show_callback = JavaScriptBridge.create_callback(_on_web_page_show)
	_web_page_hide_callback = JavaScriptBridge.create_callback(_on_web_page_hide)
	_web_visibility_change_callback = JavaScriptBridge.create_callback(_on_web_visibility_change)

	window.addEventListener("focus", _web_focus_callback)
	window.addEventListener("blur", _web_blur_callback)
	window.addEventListener("pageshow", _web_page_show_callback)
	window.addEventListener("pagehide", _web_page_hide_callback)
	document.addEventListener("visibilitychange", _web_visibility_change_callback)
	_debug_master_handoff("connected web lifecycle events")


func _on_web_focus(__: Array) -> void:
	_update_web_handoff_active("web focus")
	_debug_master_handoff("web focus observed: state={%s}" % _get_network_debug_state())


func _on_web_blur(__: Array) -> void:
	_update_web_handoff_active("web blur")
	_debug_master_handoff("web blur ignored: state={%s}" % _get_network_debug_state())


func _on_web_page_show(__: Array) -> void:
	_set_local_handoff_active(true, "web pageshow")


func _on_web_page_hide(__: Array) -> void:
	_set_local_handoff_active(false, "web pagehide")
	_try_handoff_master_client("web pagehide")


func _on_web_visibility_change(__: Array) -> void:
	var is_hidden := bool(JavaScriptBridge.eval("document.hidden", true))
	_debug_master_handoff("web visibilitychange: hidden=%s state={%s}" % [is_hidden, _get_network_debug_state()])
	if is_hidden:
		_set_local_handoff_active(false, "web visibilitychange hidden")
		_try_handoff_master_client("web visibilitychange hidden")
	else:
		_set_local_handoff_active(true, "web visibilitychange visible")


func _try_handoff_master_client(reason: String) -> void:
	_debug_master_handoff("%s state={%s}" % [reason, _get_network_debug_state()])
	if _is_active_web_master_client():
		_handoff_master_client()
	else:
		_debug_master_handoff("skipped handoff: not active web master client")


func _handoff_master_client() -> void:
	_debug_master_handoff("handoff starting: state={%s}" % _get_network_debug_state())
	var room: FusionRoom = Fusion.get_room()
	var next_player_id := _get_next_master_client_id(room)
	if next_player_id <= 0:
		_debug_master_handoff("skipped handoff: no eligible successor")
		return

	_debug_master_handoff("setting master client: %s -> %s" % [Fusion.get_local_player_id(), next_player_id])
	room.set_master_client(next_player_id)
	_debug_master_handoff("set_master_client called: target=%s state={%s}" % [next_player_id, _get_network_debug_state()])


func _is_active_web_master_client() -> bool:
	if not OS.has_feature("web"):
		_debug_master_handoff("inactive: not web")
		return false
	if not Fusion.is_master_client():
		_debug_master_handoff("inactive: not master client")
		return false
	if not Fusion.is_in_room():
		_debug_master_handoff("inactive: not in room")
		return false
	return true


func _get_next_master_client_id(room: FusionRoom) -> int:
	return _get_handoff_candidate_id(room, Fusion.get_local_player_id())


func _get_handoff_candidate_id(room: FusionRoom, excluded_player_id: int) -> int:
	var local_player_id := Fusion.get_local_player_id()
	var room_properties := room.get_custom_properties()
	_debug_master_handoff(
		"candidate scan: local_player=%s excluded=%s players=%s properties=%s" % [
			local_player_id,
			excluded_player_id,
			room.players,
			room_properties,
		]
	)

	var player_ids: Array = []
	for player: Variant in room.players:
		_debug_master_handoff("candidate entry: type=%s value=%s" % [typeof(player), player])
		if player is Dictionary and player.get("is_inactive", false):
			_debug_master_handoff("candidate rejected: inactive player=%s" % player)
			continue

		var player_id := _get_player_number(player)
		if player_id > 0 and player_id != excluded_player_id:
			player_ids.append(player_id)
			continue
		_debug_master_handoff("candidate rejected: parsed_id=%s player=%s" % [player_id, player])

	player_ids.sort()
	for player_id: int in player_ids:
		if _is_handoff_eligible_player(player_id, room_properties):
			_debug_master_handoff("candidate selected: %s" % player_id)
			return player_id
		_debug_master_handoff("candidate rejected: no fresh heartbeat player=%s" % player_id)

	return -1


func _get_player_number(player: Variant) -> int:
	if player is int:
		return player
	if player is Dictionary:
		return int(player.get("number", -1))
	return -1


func _start_handoff_heartbeat_timer() -> void:
	_handoff_heartbeat_timer = Timer.new()
	_handoff_heartbeat_timer.wait_time = HANDOFF_HEARTBEAT_INTERVAL
	_handoff_heartbeat_timer.timeout.connect(_on_handoff_heartbeat_timeout)
	add_child(_handoff_heartbeat_timer)
	_handoff_heartbeat_timer.start()


func _on_handoff_heartbeat_timeout() -> void:
	_publish_handoff_heartbeat("heartbeat", false)


func _set_local_handoff_active(is_active: bool, reason: String) -> void:
	_is_local_handoff_active = is_active
	_publish_handoff_heartbeat(reason)


func _update_web_handoff_active(reason: String) -> void:
	if not OS.has_feature("web"):
		return

	var is_active := bool(JavaScriptBridge.eval("!document.hidden", true))
	if is_active == _is_local_handoff_active:
		return

	_set_local_handoff_active(is_active, "web active poll " + reason)


func _publish_handoff_heartbeat(reason: String, log_skips := true) -> void:
	if not Fusion.is_in_room():
		if log_skips:
			_debug_master_handoff("heartbeat skipped: not in room reason=%s state={%s}" % [reason, _get_network_debug_state()])
		return

	var local_player_id := Fusion.get_local_player_id()
	if local_player_id <= 0:
		if log_skips:
			_debug_master_handoff("heartbeat skipped: no local player reason=%s state={%s}" % [reason, _get_network_debug_state()])
		return

	var room: FusionRoom = Fusion.get_room()
	var heartbeat_value := Fusion.get_network_time() if _is_local_handoff_active else -1.0
	var property_key := _get_handoff_property_key(local_player_id)
	var success := room.set_property(property_key, heartbeat_value)

	if reason != "heartbeat" or not success:
		_debug_master_handoff(
			"heartbeat publish: reason=%s active=%s key=%s value=%s success=%s state={%s}" % [
				reason,
				_is_local_handoff_active,
				property_key,
				heartbeat_value,
				success,
				_get_network_debug_state(),
			]
		)


func _is_handoff_eligible_player(player_id: int, room_properties: Dictionary) -> bool:
	var property_key := _get_handoff_property_key(player_id)
	if not room_properties.has(property_key):
		_debug_master_handoff("heartbeat missing: player=%s key=%s" % [player_id, property_key])
		return false

	var heartbeat_value: Variant = room_properties[property_key]
	if not (heartbeat_value is int or heartbeat_value is float):
		_debug_master_handoff(
			"heartbeat invalid: player=%s key=%s value=%s type=%s" % [
				player_id,
				property_key,
				heartbeat_value,
				typeof(heartbeat_value),
			]
		)
		return false

	var heartbeat_time := float(heartbeat_value)
	if heartbeat_time < 0.0:
		_debug_master_handoff(
			"heartbeat inactive: player=%s key=%s value=%s" % [
				player_id,
				property_key,
				heartbeat_value,
			]
		)
		return false

	var age := Fusion.get_network_time() - heartbeat_time
	var is_fresh := age <= HANDOFF_HEARTBEAT_TIMEOUT
	_debug_master_handoff(
		"heartbeat check: player=%s key=%s value=%s age=%s fresh=%s" % [
			player_id,
			property_key,
			heartbeat_value,
			age,
			is_fresh,
		]
	)
	return is_fresh


func _get_handoff_property_key(player_id: int) -> String:
	return HANDOFF_PROPERTY_PREFIX + str(player_id)


func _get_network_debug_state() -> String:
	var room_name := ""
	var room_master_id := -1
	var player_count := 0
	var players: Variant = []
	var room_properties: Variant = {}

	if Fusion.is_in_room():
		var room: FusionRoom = Fusion.get_room()
		room_name = room.get_room_name()
		room_master_id = room.get_master_client_id()
		player_count = room.get_player_count()
		players = room.players
		room_properties = room.get_custom_properties()

	return "web=%s connected=%s in_room=%s is_master=%s local=%s local_handoff_active=%s room=%s room_master=%s player_count=%s players=%s room_properties=%s" % [
		OS.has_feature("web"),
		Fusion.is_connected_to_photon(),
		Fusion.is_in_room(),
		Fusion.is_master_client(),
		Fusion.get_local_player_id(),
		_is_local_handoff_active,
		room_name,
		room_master_id,
		player_count,
		players,
		room_properties,
	]


func _debug_master_handoff(message: String) -> void:
	if not DEBUG_MASTER_HANDOFF:
		return

	print("[NetworkManager] master handoff t=%s: %s" % [Time.get_ticks_msec(), message])
