extends RefCounted

enum Profile {
	PRODUCTION_BASELINE,
	RPC_PULSE_RAW_DEFAULT,
	RPC_MARKER_RAW_DEFAULT,
	RAW_DEFAULT_SPEED_1X,
	RAW_DEFAULT_SPEED_2X,
	RAW_DEFAULT_SPEED_5X,
	BEST_CASE_ATTEMPT,
	WORST_CASE_ATTEMPT,
	RATE_60_ONLY,
	SMOOTHING_OFF_ONLY,
	SMOOTH_TIME_005_ONLY,
	SMOOTH_TIME_015_ONLY,
	SNAP_DISTANCE_5_ONLY,
	UPDATE_INTERVAL_6_ONLY,
	DEFAULT_PRIORITY_1_ONLY,
	AREA_INTEREST_BASE_SEND_1_ONLY,
}

const ACTIVE_PROFILE := Profile.PRODUCTION_BASELINE


static func get_active_profile_id() -> int:
	return ACTIVE_PROFILE


static func get_active_profile() -> Dictionary:
	return get_profile(ACTIVE_PROFILE)


static func get_active_room_name() -> String:
	return "lobby_" + str(get_active_profile()["id"])


static func get_active_room_options() -> Dictionary:
	return get_room_options(ACTIVE_PROFILE)


static func describe_active_profile() -> String:
	return describe_profile(ACTIVE_PROFILE)


static func get_room_options(profile_id: int) -> Dictionary:
	var profile := get_profile(profile_id)
	return {
		"fusion_config": {
			"SimulationMode": "Shared",
			"RoomSendRate": profile["room_send_rate"],
			"ClientSendRate": profile["client_send_rate"],
			"AuthoritySendRate": profile["authority_send_rate"],
			"DefaultPriority": profile["default_priority"],
		}
	}


static func describe_profile(profile_id: int) -> String:
	var profile := get_profile(profile_id)
	var replicator: Dictionary = profile["replicator"]
	var interest_area: Dictionary = profile["interest_area"]
	return "%s rates=%s/%s/%s priority=%s update_interval=%s interest_mode=%s area_enabled=%s area_base_send_rate=%s smoothing=%s smooth_time=%s snap=%s speed=%sx rpc_pulse_hz=%s rpc_marker=%s" % [
		profile["id"],
		profile["room_send_rate"],
		profile["client_send_rate"],
		profile["authority_send_rate"],
		profile["default_priority"],
		replicator["update_interval"],
		replicator["interest_mode"],
		interest_area["enabled"],
		interest_area["base_send_rate"],
		replicator["root_smoothing"],
		replicator["root_smooth_time"],
		replicator["root_snap_distance"],
		profile["speed_multiplier"],
		profile["rpc_pulse_hz"],
		profile["rpc_marker_enabled"],
	]


static func get_profile(profile_id: int) -> Dictionary:
	var profile := _production_baseline()

	match profile_id:
		Profile.PRODUCTION_BASELINE:
			pass
		Profile.RPC_PULSE_RAW_DEFAULT:
			profile["id"] = "rpc_pulse_raw_default"
			profile["description"] = "Default 30 Hz/no-area replication with smoothing disabled plus a 30 Hz RPC pulse to compare transport delivery against root position updates."
			profile["replicator"]["root_smoothing"] = false
			profile["rpc_pulse_hz"] = 30.0
		Profile.RPC_MARKER_RAW_DEFAULT:
			profile["id"] = "rpc_marker_raw_default"
			profile["description"] = "Default 30 Hz/no-area replication with smoothing disabled plus a 30 Hz RPC position marker to compare a custom position stream against built-in root updates."
			profile["replicator"]["root_smoothing"] = false
			profile["rpc_pulse_hz"] = 30.0
			profile["rpc_marker_enabled"] = true
		Profile.RAW_DEFAULT_SPEED_1X:
			profile["id"] = "raw_default_speed1x"
			profile["description"] = "Default 30 Hz/no-area replication with smoothing disabled only to expose raw sync rate; player speed stays at 1x."
			profile["replicator"]["root_smoothing"] = false
		Profile.RAW_DEFAULT_SPEED_2X:
			profile["id"] = "raw_default_speed2x"
			profile["description"] = "Default 30 Hz/no-area replication with smoothing disabled only to expose raw sync rate; player speed is 2x."
			profile["replicator"]["root_smoothing"] = false
			profile["speed_multiplier"] = 2.0
		Profile.RAW_DEFAULT_SPEED_5X:
			profile["id"] = "raw_default_speed5x"
			profile["description"] = "Default 30 Hz/no-area replication with smoothing disabled only to expose raw sync rate; player speed is 5x."
			profile["replicator"]["root_smoothing"] = false
			profile["speed_multiplier"] = 5.0
		Profile.BEST_CASE_ATTEMPT:
			profile["id"] = "best_rate60_smooth005"
			profile["description"] = "Combined best-case attempt: higher send rates plus tighter smoothing, no area-interest bandwidth spike."
			profile["room_send_rate"] = 60
			profile["client_send_rate"] = 60
			profile["authority_send_rate"] = 60
			profile["replicator"]["root_smooth_time"] = 0.05
		Profile.WORST_CASE_ATTEMPT:
			profile["id"] = "worst_interval6_raw"
			profile["description"] = "Combined worst-case attempt: old throttled update interval with smoothing disabled."
			profile["replicator"]["update_interval"] = 6
			profile["replicator"]["root_smoothing"] = false
		Profile.RATE_60_ONLY:
			profile["id"] = "factor_rate60_only"
			profile["description"] = "Only changes room/client/authority send rates from 30 to 60."
			profile["room_send_rate"] = 60
			profile["client_send_rate"] = 60
			profile["authority_send_rate"] = 60
		Profile.SMOOTHING_OFF_ONLY:
			profile["id"] = "factor_smoothing_off_only"
			profile["description"] = "Only disables root smoothing to expose raw remote root cadence."
			profile["replicator"]["root_smoothing"] = false
		Profile.SMOOTH_TIME_005_ONLY:
			profile["id"] = "factor_smooth_time005_only"
			profile["description"] = "Only changes root_smooth_time from 0.08 to 0.05."
			profile["replicator"]["root_smooth_time"] = 0.05
		Profile.SMOOTH_TIME_015_ONLY:
			profile["id"] = "factor_smooth_time015_only"
			profile["description"] = "Only changes root_smooth_time from 0.08 to 0.15."
			profile["replicator"]["root_smooth_time"] = 0.15
		Profile.SNAP_DISTANCE_5_ONLY:
			profile["id"] = "factor_snap5_only"
			profile["description"] = "Only changes root_snap_distance from 100 to 5."
			profile["replicator"]["root_snap_distance"] = 5.0
		Profile.UPDATE_INTERVAL_6_ONLY:
			profile["id"] = "factor_interval6_only"
			profile["description"] = "Only changes FusionSharedReplicator.update_interval from 1 to 6."
			profile["replicator"]["update_interval"] = 6
		Profile.DEFAULT_PRIORITY_1_ONLY:
			profile["id"] = "factor_priority1_only"
			profile["description"] = "Only changes Fusion config DefaultPriority from 2 to 1."
			profile["default_priority"] = 1
		Profile.AREA_INTEREST_BASE_SEND_1_ONLY:
			profile["id"] = "factor_area_base1_only"
			profile["description"] = "Only enables explicit area interest with base_send_rate=1, keeping smoothing enabled."
			profile["replicator"]["interest_mode"] = 1
			profile["interest_area"]["enabled"] = true
			profile["interest_area"]["base_send_rate"] = 1
		_:
			push_warning("Unknown NetworkTestProfile id %s; using production baseline." % profile_id)

	return profile


static func _production_baseline() -> Dictionary:
	return {
		"id": "production_baseline",
		"description": "Current confirmed production candidate.",
		"speed_multiplier": 1.0,
		"rpc_pulse_hz": 0.0,
		"rpc_marker_enabled": false,
		"room_send_rate": 30,
		"client_send_rate": 30,
		"authority_send_rate": 30,
		"default_priority": 2,
		"replicator": {
			"update_interval": 1,
			"owner_mode": 1,
			"interest_mode": 0,
			"root_replication_mode": 1,
			"root_smoothing": true,
			"root_smooth_time": 0.08,
			"root_snap_distance": 100.0,
		},
		"interest_area": {
			"enabled": false,
			"orientation": 0,
			"grid_size": 21,
			"base_send_rate": 1,
			"decay_mode": 0,
		},
	}
