class_name Player extends CharacterBody2D

const NetworkTestProfile = preload("res://tests/network_test_profile.gd")

const SPEED = 100.0
const JUMP_VELOCITY = -400.0
const NETWORK_DIAGNOSTICS_ENABLED := false
const NETWORK_DIAGNOSTICS_INTERVAL := 2.0
const RPC_POSITION_MARKER_TEXTURE = preload("res://icon.svg")
const RPC_POSITION_MARKER_VISUAL_OFFSET := Vector2(0.0, -30.0)

@onready var _replicator: FusionSharedReplicator = %FusionSharedReplicator

var _speed := SPEED
var _rpc_pulse_hz := 0.0
var _rpc_marker_enabled := false
var _rpc_position_marker: Sprite2D
var _diag_rpc_send_elapsed := 0.0
var _diag_rpc_sequence_id := 0
var _diag_elapsed := 0.0
var _diag_physics_ticks := 0
var _diag_position_changes := 0
var _diag_last_position := Vector2.INF
var _diag_last_change_usec := 0
var _diag_change_interval_sum := 0.0
var _diag_change_interval_min := INF
var _diag_change_interval_max := 0.0
var _diag_change_distance_sum := 0.0
var _diag_change_distance_min := INF
var _diag_change_distance_max := 0.0
var _diag_rpc_received := 0
var _diag_rpc_last_sequence_id := -1
var _diag_rpc_sequence_gaps := 0
var _diag_rpc_last_receive_usec := 0
var _diag_rpc_interval_sum := 0.0
var _diag_rpc_interval_min := INF
var _diag_rpc_interval_max := 0.0
var _diag_rpc_root_delta_sum := 0.0
var _diag_rpc_root_delta_max := 0.0
var _diag_rpc_marker_changes := 0
var _diag_rpc_marker_last_position := Vector2.INF
var _diag_rpc_marker_last_change_usec := 0
var _diag_rpc_marker_interval_sum := 0.0
var _diag_rpc_marker_interval_min := INF
var _diag_rpc_marker_interval_max := 0.0
var _diag_rpc_marker_distance_sum := 0.0
var _diag_rpc_marker_distance_min := INF
var _diag_rpc_marker_distance_max := 0.0
var _diag_rotation_min_deg := INF
var _diag_rotation_max_deg := -INF
var _diag_global_rotation_min_deg := INF
var _diag_global_rotation_max_deg := -INF
var _diag_scale_x_min := INF
var _diag_scale_x_max := -INF
var _diag_scale_y_min := INF
var _diag_scale_y_max := -INF


func _ready() -> void:
	_apply_network_test_profile()
	_print_replicator_diagnostics()
	if not _replicator.has_authority():
		# Match Photon Starter: do not let Godot's physics interpolation fight
		# Fusion's network smoothing on remote player roots.
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		set_physics_process(false)
		if not NETWORK_DIAGNOSTICS_ENABLED:
			set_process(false)
		set_process_input(false)
		set_process_shortcut_input(false)
		set_process_unhandled_input(false)
		set_process_unhandled_key_input(false)
		_ensure_rpc_position_marker()


func _apply_network_test_profile() -> void:
	var profile := NetworkTestProfile.get_active_profile()
	_speed = SPEED * float(profile["speed_multiplier"])
	_rpc_pulse_hz = float(profile["rpc_pulse_hz"])
	_rpc_marker_enabled = bool(profile["rpc_marker_enabled"])
	var replicator_config: Dictionary = profile["replicator"]
	for property_name in replicator_config.keys():
		_replicator.set(property_name, replicator_config[property_name])

	_configure_interest_area(profile["interest_area"])

	if NETWORK_DIAGNOSTICS_ENABLED:
		print("[PlayerDiag] test_profile=", NetworkTestProfile.describe_active_profile(),
			" description=", profile["description"])


func _configure_interest_area(interest_area_config: Dictionary) -> void:
	var interest_area := get_node_or_null("FusionInterestArea") as Node
	if not bool(interest_area_config["enabled"]):
		if interest_area != null:
			remove_child(interest_area)
			interest_area.free()
		return

	if interest_area == null:
		interest_area = ClassDB.instantiate("FusionInterestArea") as Node
		if interest_area == null:
			push_warning("Unable to instantiate FusionInterestArea for the active network test profile.")
			return
		interest_area.name = "FusionInterestArea"
		add_child(interest_area)

	interest_area.set("enabled", true)
	interest_area.set("orientation", interest_area_config["orientation"])
	interest_area.set("grid_size", interest_area_config["grid_size"])
	interest_area.set("base_send_rate", interest_area_config["base_send_rate"])
	interest_area.set("decay_mode", interest_area_config["decay_mode"])


func _process(delta: float) -> void:
	if not NETWORK_DIAGNOSTICS_ENABLED:
		return

	_diag_elapsed += delta
	_record_transform_diagnostics()

	if not _replicator.has_authority():
		_record_remote_position_change()

	if _diag_elapsed >= NETWORK_DIAGNOSTICS_INTERVAL:
		_print_player_network_diagnostics()
		_reset_player_network_diagnostics()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("use"):
		interact("use")
		return
	
	if event.is_action_pressed("ui_up"):
		interact("use_up")
		return
	
	if event.is_action_pressed("ui_down"):
		interact("use_down")
		return


func interact(method: StringName) -> void:
	for area in %InteractionArea.get_overlapping_areas():
		if not area.has_method(method):
			continue
		
		area.call(method, self)


func _physics_process(delta: float) -> void:
	if NETWORK_DIAGNOSTICS_ENABLED:
		_diag_physics_ticks += 1

	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var direction := Input.get_axis("ui_left", "ui_right")
	if direction:
		velocity.x = direction * _speed
	else:
		velocity.x = move_toward(velocity.x, 0, _speed)

	move_and_slide()

	_send_rpc_diagnostic_pulse(delta)


func _send_rpc_diagnostic_pulse(delta: float) -> void:
	if _rpc_pulse_hz <= 0.0:
		return
	if not _replicator.has_authority():
		return

	_diag_rpc_send_elapsed += delta
	var pulse_interval := 1.0 / _rpc_pulse_hz
	while _diag_rpc_send_elapsed >= pulse_interval:
		_diag_rpc_send_elapsed -= pulse_interval
		_diag_rpc_sequence_id += 1
		Fusion.rpc(rpc_netdiag_pulse, _diag_rpc_sequence_id, global_position.x, global_position.y)


@rpc("call_local")
func rpc_netdiag_pulse(sequence_id: int, sent_x: float, sent_y: float) -> void:
	if _replicator.has_authority():
		return

	_diag_rpc_received += 1

	if _diag_rpc_last_sequence_id >= 0 and sequence_id > _diag_rpc_last_sequence_id + 1:
		_diag_rpc_sequence_gaps += sequence_id - _diag_rpc_last_sequence_id - 1
	_diag_rpc_last_sequence_id = sequence_id

	var now_usec := Time.get_ticks_usec()
	if _diag_rpc_last_receive_usec > 0:
		var interval := float(now_usec - _diag_rpc_last_receive_usec) / 1000000.0
		_diag_rpc_interval_sum += interval
		_diag_rpc_interval_min = minf(_diag_rpc_interval_min, interval)
		_diag_rpc_interval_max = maxf(_diag_rpc_interval_max, interval)
	_diag_rpc_last_receive_usec = now_usec

	var sent_position := Vector2(sent_x, sent_y)
	var root_delta := global_position.distance_to(sent_position)
	_diag_rpc_root_delta_sum += root_delta
	_diag_rpc_root_delta_max = maxf(_diag_rpc_root_delta_max, root_delta)

	_apply_rpc_position_marker(sent_position)


func _ensure_rpc_position_marker() -> void:
	if not _rpc_marker_enabled:
		return
	if _replicator.has_authority():
		return
	if _rpc_position_marker != null:
		return

	_rpc_position_marker = Sprite2D.new()
	_rpc_position_marker.name = "RpcPositionMarker"
	_rpc_position_marker.texture = RPC_POSITION_MARKER_TEXTURE
	_rpc_position_marker.scale = Vector2(0.125, 0.25)
	_rpc_position_marker.modulate = Color(0.1, 1.0, 0.25, 0.65)
	_rpc_position_marker.position = RPC_POSITION_MARKER_VISUAL_OFFSET
	_rpc_position_marker.z_index = 100
	add_child(_rpc_position_marker)


func _apply_rpc_position_marker(sent_position: Vector2) -> void:
	if not _rpc_marker_enabled:
		return

	_ensure_rpc_position_marker()
	if _rpc_position_marker != null:
		_rpc_position_marker.global_position = sent_position + RPC_POSITION_MARKER_VISUAL_OFFSET

	_record_rpc_position_marker_change(sent_position)


func _print_replicator_diagnostics() -> void:
	if not NETWORK_DIAGNOSTICS_ENABLED:
		return

	print("[PlayerDiag] ready name=", name,
		" authority=", _replicator.has_authority(),
		" owner_id=", _replicator.get_owner_id(),
		" speed=", snappedf(_speed, 0.1),
		" rpc_pulse_hz=", snappedf(_rpc_pulse_hz, 0.1),
		" rpc_marker=", _rpc_marker_enabled,
		" rpc_marker_offset=", RPC_POSITION_MARKER_VISUAL_OFFSET,
		" rotation_deg=", snappedf(rotation_degrees, 0.01),
		" global_rotation_deg=", snappedf(global_rotation_degrees, 0.01),
		" scale=", scale,
		" update_interval=", _replicator.get("update_interval"),
		" interest_mode=", _replicator.get_interest_mode(),
		" interest_key=", _replicator.get_interest_key(),
		" root_mode=", _replicator.get_root_replication_mode(),
		" root_smoothing=", _replicator.get_root_smoothing(),
		" smooth_time=", snappedf(_replicator.get_root_smooth_time(), 0.001),
		" snap_distance=", snappedf(_replicator.get_root_snap_distance(), 0.001),
		" interpolation=", _replicator.get_root_interpolation_mode(),
		" snapshot_delay=", _replicator.get_root_snapshot_delay(),
		" max_snapshot_gap=", snappedf(_replicator.get_root_max_snapshot_gap(), 0.001),
		" max_delay=", snappedf(_replicator.get_root_max_delay(), 0.001),
		" min_position_error=", snappedf(_replicator.get_root_min_position_error(), 0.01),
		" min_rotation_error=", snappedf(_replicator.get_root_min_rotation_error(), 0.01),
		" physics_interp_mode=", physics_interpolation_mode)

	var interest_area := get_node_or_null("FusionInterestArea") as FusionInterestArea
	if interest_area != null:
		print("[PlayerDiag] interest_area name=", name,
			" orientation=", interest_area.get_orientation(),
			" grid_size=", interest_area.get_grid_size(),
			" base_send_rate=", interest_area.get_base_send_rate(),
			" decay_mode=", interest_area.get_decay_mode(),
			" enabled=", interest_area.get_enabled())


func _record_remote_position_change() -> void:
	if _diag_last_position == Vector2.INF:
		_diag_last_position = global_position
		return

	var change_distance := global_position.distance_to(_diag_last_position)
	if change_distance <= 0.01:
		return

	var now_usec := Time.get_ticks_usec()
	if _diag_last_change_usec > 0:
		var interval := float(now_usec - _diag_last_change_usec) / 1000000.0
		_diag_change_interval_sum += interval
		_diag_change_interval_min = minf(_diag_change_interval_min, interval)
		_diag_change_interval_max = maxf(_diag_change_interval_max, interval)

	_diag_change_distance_sum += change_distance
	_diag_change_distance_min = minf(_diag_change_distance_min, change_distance)
	_diag_change_distance_max = maxf(_diag_change_distance_max, change_distance)

	_diag_last_change_usec = now_usec
	_diag_last_position = global_position
	_diag_position_changes += 1


func _record_rpc_position_marker_change(sent_position: Vector2) -> void:
	if _diag_rpc_marker_last_position == Vector2.INF:
		_diag_rpc_marker_last_position = sent_position
		return

	var change_distance := sent_position.distance_to(_diag_rpc_marker_last_position)
	if change_distance <= 0.01:
		return

	var now_usec := Time.get_ticks_usec()
	if _diag_rpc_marker_last_change_usec > 0:
		var interval := float(now_usec - _diag_rpc_marker_last_change_usec) / 1000000.0
		_diag_rpc_marker_interval_sum += interval
		_diag_rpc_marker_interval_min = minf(_diag_rpc_marker_interval_min, interval)
		_diag_rpc_marker_interval_max = maxf(_diag_rpc_marker_interval_max, interval)

	_diag_rpc_marker_distance_sum += change_distance
	_diag_rpc_marker_distance_min = minf(_diag_rpc_marker_distance_min, change_distance)
	_diag_rpc_marker_distance_max = maxf(_diag_rpc_marker_distance_max, change_distance)

	_diag_rpc_marker_last_change_usec = now_usec
	_diag_rpc_marker_last_position = sent_position
	_diag_rpc_marker_changes += 1


func _record_transform_diagnostics() -> void:
	_diag_rotation_min_deg = minf(_diag_rotation_min_deg, rotation_degrees)
	_diag_rotation_max_deg = maxf(_diag_rotation_max_deg, rotation_degrees)
	_diag_global_rotation_min_deg = minf(_diag_global_rotation_min_deg, global_rotation_degrees)
	_diag_global_rotation_max_deg = maxf(_diag_global_rotation_max_deg, global_rotation_degrees)
	_diag_scale_x_min = minf(_diag_scale_x_min, scale.x)
	_diag_scale_x_max = maxf(_diag_scale_x_max, scale.x)
	_diag_scale_y_min = minf(_diag_scale_y_min, scale.y)
	_diag_scale_y_max = maxf(_diag_scale_y_max, scale.y)


func _print_player_network_diagnostics() -> void:
	var is_authority := _replicator.has_authority()
	var changes_per_second := float(_diag_position_changes) / maxf(_diag_elapsed, 0.001)
	var avg_change_interval := 0.0
	if _diag_position_changes > 1:
		avg_change_interval = _diag_change_interval_sum / float(_diag_position_changes - 1)
	var avg_change_distance := 0.0
	if _diag_position_changes > 0:
		avg_change_distance = _diag_change_distance_sum / float(_diag_position_changes)
	var avg_remote_speed := 0.0
	if _diag_change_interval_sum > 0.0:
		avg_remote_speed = _diag_change_distance_sum / _diag_change_interval_sum
	var rpc_pulses_per_second := float(_diag_rpc_received) / maxf(_diag_elapsed, 0.001)
	var avg_rpc_interval := 0.0
	if _diag_rpc_received > 1:
		avg_rpc_interval = _diag_rpc_interval_sum / float(_diag_rpc_received - 1)
	var avg_rpc_root_delta := 0.0
	if _diag_rpc_received > 0:
		avg_rpc_root_delta = _diag_rpc_root_delta_sum / float(_diag_rpc_received)
	var rpc_marker_changes_per_second := float(_diag_rpc_marker_changes) / maxf(_diag_elapsed, 0.001)
	var avg_rpc_marker_interval := 0.0
	if _diag_rpc_marker_changes > 1:
		avg_rpc_marker_interval = _diag_rpc_marker_interval_sum / float(_diag_rpc_marker_changes - 1)
	var avg_rpc_marker_distance := 0.0
	if _diag_rpc_marker_changes > 0:
		avg_rpc_marker_distance = _diag_rpc_marker_distance_sum / float(_diag_rpc_marker_changes)

	print("[PlayerDiag] name=", name,
		" authority=", is_authority,
		" owner_id=", _replicator.get_owner_id(),
		" fps=", Performance.get_monitor(Performance.TIME_FPS),
		" physics_ticks_per_sec=", snappedf(float(_diag_physics_ticks) / maxf(_diag_elapsed, 0.001), 0.1),
		" rotation_deg=", snappedf(rotation_degrees, 0.01),
		" global_rotation_deg=", snappedf(global_rotation_degrees, 0.01),
		" rotation_window_deg=(", snappedf(_diag_rotation_min_deg, 0.01), ", ", snappedf(_diag_rotation_max_deg, 0.01), ")",
		" global_rotation_window_deg=(", snappedf(_diag_global_rotation_min_deg, 0.01), ", ", snappedf(_diag_global_rotation_max_deg, 0.01), ")",
		" scale=", scale,
		" scale_window=(", Vector2(snappedf(_diag_scale_x_min, 0.001), snappedf(_diag_scale_y_min, 0.001)),
			", ", Vector2(snappedf(_diag_scale_x_max, 0.001), snappedf(_diag_scale_y_max, 0.001)), ")",
		" remote_pos_changes_per_sec=", snappedf(changes_per_second, 0.1),
		" avg_change_ms=", snappedf(avg_change_interval * 1000.0, 0.1),
		" min_change_ms=", snappedf(_diag_change_interval_min * 1000.0, 0.1) if _diag_change_interval_min < INF else -1.0,
		" max_change_ms=", snappedf(_diag_change_interval_max * 1000.0, 0.1),
		" avg_step_px=", snappedf(avg_change_distance, 0.01),
		" min_step_px=", snappedf(_diag_change_distance_min, 0.01) if _diag_change_distance_min < INF else -1.0,
		" max_step_px=", snappedf(_diag_change_distance_max, 0.01),
		" avg_remote_speed=", snappedf(avg_remote_speed, 0.1),
		" rpc_pulses_per_sec=", snappedf(rpc_pulses_per_second, 0.1),
		" avg_rpc_ms=", snappedf(avg_rpc_interval * 1000.0, 0.1),
		" min_rpc_ms=", snappedf(_diag_rpc_interval_min * 1000.0, 0.1) if _diag_rpc_interval_min < INF else -1.0,
		" max_rpc_ms=", snappedf(_diag_rpc_interval_max * 1000.0, 0.1),
		" rpc_seq_gaps=", _diag_rpc_sequence_gaps,
		" avg_rpc_root_delta_px=", snappedf(avg_rpc_root_delta, 0.01),
		" max_rpc_root_delta_px=", snappedf(_diag_rpc_root_delta_max, 0.01),
		" rpc_marker_changes_per_sec=", snappedf(rpc_marker_changes_per_second, 0.1),
		" avg_rpc_marker_ms=", snappedf(avg_rpc_marker_interval * 1000.0, 0.1),
		" min_rpc_marker_ms=", snappedf(_diag_rpc_marker_interval_min * 1000.0, 0.1) if _diag_rpc_marker_interval_min < INF else -1.0,
		" max_rpc_marker_ms=", snappedf(_diag_rpc_marker_interval_max * 1000.0, 0.1),
		" avg_rpc_marker_step_px=", snappedf(avg_rpc_marker_distance, 0.01),
		" max_rpc_marker_step_px=", snappedf(_diag_rpc_marker_distance_max, 0.01),
		" position=", global_position,
		" velocity=", velocity)


func _reset_player_network_diagnostics() -> void:
	_diag_elapsed = 0.0
	_diag_physics_ticks = 0
	_diag_position_changes = 0
	_diag_change_interval_sum = 0.0
	_diag_change_interval_min = INF
	_diag_change_interval_max = 0.0
	_diag_change_distance_sum = 0.0
	_diag_change_distance_min = INF
	_diag_change_distance_max = 0.0
	_diag_rpc_received = 0
	_diag_rpc_last_sequence_id = -1
	_diag_rpc_sequence_gaps = 0
	_diag_rpc_last_receive_usec = 0
	_diag_rpc_interval_sum = 0.0
	_diag_rpc_interval_min = INF
	_diag_rpc_interval_max = 0.0
	_diag_rpc_root_delta_sum = 0.0
	_diag_rpc_root_delta_max = 0.0
	_diag_rpc_marker_changes = 0
	_diag_rpc_marker_interval_sum = 0.0
	_diag_rpc_marker_interval_min = INF
	_diag_rpc_marker_interval_max = 0.0
	_diag_rpc_marker_distance_sum = 0.0
	_diag_rpc_marker_distance_min = INF
	_diag_rpc_marker_distance_max = 0.0
	_diag_rotation_min_deg = INF
	_diag_rotation_max_deg = -INF
	_diag_global_rotation_min_deg = INF
	_diag_global_rotation_max_deg = -INF
	_diag_scale_x_min = INF
	_diag_scale_x_max = -INF
	_diag_scale_y_min = INF
	_diag_scale_y_max = -INF
