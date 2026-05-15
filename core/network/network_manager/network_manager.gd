extends CanvasLayer

const NetworkTestProfile = preload("res://tests/network_test_profile.gd")

const network_diagnostics_enabled := false
const network_diagnostics_interval := 2.0

var lobby_room_name: String = NetworkTestProfile.get_active_room_name()
var room_options: Dictionary = NetworkTestProfile.get_active_room_options()

var _network_diagnostics_timer: Timer
var _last_network_time := 0.0
var _last_stats_usec := 0


func _ready() -> void:
	connect_to_lobby.call_deferred()
	start_network_diagnostics.call_deferred()


func connect_to_lobby() -> void:
	Fusion.connected_to_photon.connect(func():
		print("[NetDiag] connected_to_photon; joining room=", lobby_room_name,
			" requested_options=", room_options)
		Fusion.join_or_create_room(lobby_room_name, room_options)
	)
	Fusion.room_joined.connect(_on_room_joined)
	Fusion.connection_status_changed.connect(func(status: FusionClient.ConnectionStatus):
		print("[NetDiag] connection_status=", status)
	)
	Fusion.connect_to_photon()


func start_network_diagnostics() -> void:
	if not network_diagnostics_enabled:
		return

	_print_runtime_config()
	_network_diagnostics_timer = Timer.new()
	_network_diagnostics_timer.wait_time = network_diagnostics_interval
	_network_diagnostics_timer.timeout.connect(_print_network_stats)
	_network_diagnostics_timer.autostart = true
	add_child(_network_diagnostics_timer)


func _on_room_joined() -> void:
	print("[NetDiag] room_joined local_player_id=", Fusion.get_local_player_id())
	_print_room_config()


func _print_runtime_config() -> void:
	print("[NetDiag] test_profile=", NetworkTestProfile.describe_active_profile(),
		" description=", NetworkTestProfile.get_active_profile()["description"])
	print("[NetDiag] runtime max_fps=", Engine.max_fps,
		" project_max_fps=", ProjectSettings.get_setting("application/run/max_fps"),
		" print_fps=", ProjectSettings.get_setting("debug/settings/stdout/print_fps"),
		" physics_tps=", Engine.physics_ticks_per_second,
		" physics_interpolation=", ProjectSettings.get_setting("physics/common/physics_interpolation"),
		" low_processor=", ProjectSettings.get_setting("application/run/low_processor_mode"))
	print("[NetDiag] fusion settings process_mode=", ProjectSettings.get_setting("fusion/simulation/process_mode"),
		" simulation_mode=", ProjectSettings.get_setting("fusion/simulation/mode"),
		" region=", ProjectSettings.get_setting("fusion/connection/default_region"),
		" float_compression=", ProjectSettings.get_setting("fusion/serialization/float_compression"))
	if Engine.max_fps > 0 and Engine.max_fps <= 30:
		print("[NetDiag] WARNING: Engine.max_fps is capped at ", Engine.max_fps,
			". This will make network motion look like the cap even if Fusion sends faster.")


func _print_room_config() -> void:
	var room := Fusion.get_room()
	if room == null:
		print("[NetDiag] room_config unavailable")
		return

	var custom_properties := room.get_custom_properties()
	print("[NetDiag] room name=", room.get_room_name(),
		" players=", room.get_player_count(),
		" master=", room.get_master_client_id(),
		" fusion_config=", custom_properties.get("fusion_config", "<missing>"))


func _print_network_stats() -> void:
	var now_usec := Time.get_ticks_usec()
	var elapsed := 0.0
	if _last_stats_usec > 0:
		elapsed = float(now_usec - _last_stats_usec) / 1000000.0
	_last_stats_usec = now_usec

	var network_time := Fusion.get_network_time() if Fusion.is_in_room() else 0.0
	var network_delta := network_time - _last_network_time if _last_network_time > 0.0 else 0.0
	_last_network_time = network_time

	var room := Fusion.get_room() if Fusion.is_in_room() else null
	var player_count := room.get_player_count() if room != null else 0

	print("[NetDiag] fps=", Performance.get_monitor(Performance.TIME_FPS),
		" elapsed=", snappedf(elapsed, 0.001),
		" in_room=", Fusion.is_in_room(),
		" players=", player_count,
		" rtt=", snappedf(Fusion.get_rtt(), 0.001),
		" network_time=", snappedf(network_time, 0.001),
		" network_delta=", snappedf(network_delta, 0.001),
		" sent_bps=", snappedf(_fusion_monitor(&"_get_monitor_bps_sent"), 0.1),
		" recv_bps=", snappedf(_fusion_monitor(&"_get_monitor_bps_recv"), 0.1),
		" sync_out_us=", snappedf(_fusion_monitor(&"_get_monitor_sync_outbound_us"), 0.1),
		" sync_in_us=", snappedf(_fusion_monitor(&"_get_monitor_sync_inbound_us"), 0.1),
		" service_us=", snappedf(_fusion_monitor(&"_get_monitor_service_us"), 0.1),
		" update_us=", snappedf(_fusion_monitor(&"_get_monitor_update_total_us"), 0.1))


func _fusion_monitor(method: StringName) -> float:
	if not Fusion.has_method(method):
		return -1.0
	return float(Fusion.call(method))
