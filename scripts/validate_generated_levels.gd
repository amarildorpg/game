extends SceneTree

func _init() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	# Regressão da regra central: igualdade nunca derrota um inimigo.
	var equal_enemy := {"width":2,"height":1,"start":[0,0],"goal":[1,0],"items":[],"enemies":[{"p":[1,0],"power":5}]}
	var test_config: Dictionary = game.config.duplicate(true)
	test_config.start_power = 5
	test_config.fatigue_enabled = false
	if LevelValidator.is_solvable(equal_enemy,test_config):
		push_error("Regressão: poder 5 não pode vencer inimigo 5")
		quit(1); return
	equal_enemy.enemies[0].power = 4
	if not LevelValidator.is_solvable(equal_enemy,test_config):
		push_error("Regressão: poder 5 deveria vencer inimigo 4")
		quit(1); return
	# Amostra repetida para também exercitar a aleatoriedade e a rota de emergência.
	for sample in 1:
		for i in range(mini(3,game.levels.size())):
			game._start_level(i)
			if not LevelValidator.is_solvable(game.level, game.config):
				push_error("Amostra %d: fase gerada %d impossível" % [sample+1,i+1])
				quit(1); return
	print("Validação concluída: igualdade bloqueada e %d mapas aleatórios válidos" % mini(3,game.levels.size()))
	quit(0)
