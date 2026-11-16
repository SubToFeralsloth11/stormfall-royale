extends Node
## Entry point: hands over to the Game autoload (intro -> lobby -> match).

func _ready() -> void:
	Game.play_intro()
