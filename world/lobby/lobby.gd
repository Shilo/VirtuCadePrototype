extends Node

func _ready():
	Fusion.room_joined.connect(_on_room_joined)


func _on_room_joined():
	%VirtuSpawner.spawn()
