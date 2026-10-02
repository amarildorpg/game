class_name LevelValidator
extends RefCounted

# Teto de estados explorados. Sem isso, fases com muitos inimigos podem gerar
# 2^N combinações e a busca trava o jogo (percebido como "toque parou de
# funcionar", já que tudo roda na mesma thread principal). Estourar o teto
# devolve "não solucionável" — resposta segura, pois quem chama já sabe lidar
# com isso (tenta de novo ou usa a rota de emergência garantida por BFS).
const MAX_STATES_EXPLORED := 40000

static func is_solvable(level: Dictionary, config: Dictionary) -> bool:
	var initial := {"pos": Vector2i(level.start[0], level.start[1]), "power": int(config.start_power), "items": 0, "enemies": 0, "fatigue":int(config.get("start_fatigue",0))}
	var queue: Array[Dictionary] = [initial]
	var seen := {}
	while not queue.is_empty():
		if seen.size() > MAX_STATES_EXPLORED: return false
		var state: Dictionary = queue.pop_front()
		var key := "%s:%s:%s:%s:%s" % [state.pos, state.power, state.items, state.enemies, state.fatigue]
		if seen.has(key): continue
		seen[key] = true
		if state.pos == Vector2i(level.goal[0], level.goal[1]): return true
		for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var p: Vector2i = state.pos + d
			if p.x < 0 or p.y < 0 or p.x >= int(level.width) or p.y >= int(level.height): continue
			var next := state.duplicate()
			next.pos = p
			var blocked := false
			var had_content := false
			for i in range(level.get("enemies", []).size()):
				var e: Dictionary = level.enemies[i]
				if p == Vector2i(e.p[0], e.p[1]) and not (int(state.enemies) & (1 << i)):
					had_content = true
					if int(state.power) <= int(e.power): blocked = true
					else:
						next.power += int(e.power)
						next.enemies = int(state.enemies) | (1 << i)
			for i in range(level.get("items", []).size()):
				var item: Dictionary = level.items[i]
				if p == Vector2i(item.p[0], item.p[1]) and not (int(state.items) & (1 << i)):
					had_content = true
					var cfg: Dictionary = config.items[item.type]
					next.power = int(next.power) * int(item.get("multiply", cfg.get("multiply", 1))) + int(item.get("power", cfg.get("power", 0)))
					next.items = int(state.items) | (1 << i)
			if not blocked:
				if had_content: next.fatigue = 0
				elif bool(config.get("fatigue_enabled",false)):
					next.power = maxi(1,int(next.power)-(1 << mini(int(state.fatigue),20)))
					next.fatigue = mini(int(state.fatigue)+1,20)
				queue.push_back(next)
	return false
