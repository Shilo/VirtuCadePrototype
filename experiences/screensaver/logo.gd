class_name ScreensaverLogo extends Sprite2D

@onready var replicator: FusionSharedReplicator = %FusionSharedReplicator

var velocity: Vector2 = Vector2.ZERO
var _corner_tween: Tween


func play_corner_hit() -> void:
	Fusion.rpc(rpc_corner_hit)


@rpc("authority", "call_local")
func rpc_corner_hit() -> void:
	if _corner_tween != null:
		_corner_tween.kill()

	_corner_tween = create_tween()
	_corner_tween.tween_property(self, "scale", Vector2.ONE * 1.25, 0.1)
	_corner_tween.tween_property(self, "scale", Vector2.ONE, 0.15)
