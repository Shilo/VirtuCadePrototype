extends Node

func _ready():
	Fusion.room_joined.connect(_on_room_joined)


func _on_room_joined():
	var player = %FusionSpawner.spawn()
	var angle := randf() * TAU
	var offset := Vector2(cos(angle), sin(angle)) * 16.0
	player.global_position = %Spawn.global_position + offset
