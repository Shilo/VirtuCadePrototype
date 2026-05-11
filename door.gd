class_name Door extends Area2D

@export var use_door: Door
@export var up_door: Door
@export var down_door: Door


func use(player: Player):
	_use(player, use_door)


func use_up(player: Player):
	_use(player, up_door)


func use_down(player: Player):
	_use(player, down_door)


func _use(player: Player, target_door: Door):
	if not target_door:
		return
	
	if not player:
		push_error("[VirtuMachine " + str(self) + "] Player is null.")
		return
	
	player.global_position = target_door.global_position
