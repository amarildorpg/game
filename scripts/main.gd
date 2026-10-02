extends Control

const SAVE_PATH := "user://save.json"
const MAX_STAGE := 999
const LevelValidator = preload("res://scripts/level_validator.gd")
const HERO_TEXTURE := preload("res://assets/sprites/hero-base.png")
const HERO_SIDE_TEXTURE := preload("res://assets/sprites/hero-side-transparent-v4.png")
const HERO_BACK_TEXTURE := preload("res://assets/sprites/hero-back-v3.png")
const ENEMY_SIDE_TEXTURE := preload("res://assets/sprites/enemy-side-neutral-v2.png")
const ENEMY_BACK_TEXTURE := preload("res://assets/sprites/enemy-back-neutral-v3.png")
const ATLAS_TEXTURE := preload("res://assets/sprites/character-item-atlas.png")
const EQUIPMENT_TEXTURE := preload("res://assets/sprites/equipment-atlas-v2.png")
const ATLAS_CELL := 416.0
const COMBAT_DURATION := 1.25
const DEFEAT_DURATION := 0.58
const PICKUP_MOVE_DURATION := .82
const PICKUP_LIFT_DURATION := .88
var config: Dictionary
var levels: Array
var unlocked := 1
var level_index := 0
var level: Dictionary
var player := Vector2i.ZERO
var power := 1
var lives := 3
var collected := {}
var defeated := {}
var revealed_bosses := {}
var equipment := {"weapons":[], "head":"", "helmet":false, "crown":false, "shield":false, "armor":false, "cape":false, "boots":false, "amulet":false}
var screen := "home"
var loading_progress := 0.0
var board_rect := Rect2()
var tile_size := 100.0
var feedback := ""
var feedback_alpha := 0.0
var player_bounce := 0.0
var shake := 0.0
var combat_active := false
var combat_time := 0.0
var combat_target := Vector2i.ZERO
var fatigue_chain := 0
var enemy_defeat_target := Vector2i(-1,-1)
var enemy_defeat_time := 0.0
var hero_defeat_time := 0.0
var move_direction := Vector2i.DOWN
var hero_kneeling := false
var defeat_modal := false
var pickup_active := false
var pickup_time := 0.0
var pickup_target := Vector2i.ZERO
var pickup_item_index := -1
var walk_move_active := false
var walk_move_from := Vector2i.ZERO
var walk_move_to := Vector2i.ZERO
var walk_move_time := 0.0
const WALK_MOVE_DURATION := 0.20
var pending_restart_lives := 3
var play_button := Rect2()
var retry_button := Rect2()
var close_button := Rect2()
var input_block_until_ms := 0
var quit_modal := false
var quit_confirm_button := Rect2()
var quit_cancel_button := Rect2()
var sfx_players: Dictionary = {}
const MILESTONE_STEP := 50
# A cada TIER_SIZE fases o visual muda de "bioma" — mantém as 999 fases
# visualmente variadas em vez de repetir sempre a mesma paleta bege.
const TIER_SIZE := 15
const TIER_PALETTES := [
	{"bg":"#fff7e8","tile_a":"#f2e9d9","tile_b":"#e8ddca","goal":"#62c9a5"},
	{"bg":"#eaf6f3","tile_a":"#dff0ea","tile_b":"#c9e6dc","goal":"#2fae8c"},
	{"bg":"#fdeef0","tile_a":"#f8dde1","tile_b":"#f0c6cd","goal":"#d84d63"},
	{"bg":"#eef0fb","tile_a":"#dde1f7","tile_b":"#c7cdf0","goal":"#5a68d6"},
	{"bg":"#fff3da","tile_a":"#ffe6b8","tile_b":"#f7d391","goal":"#e0932f"},
	{"bg":"#2b2440","tile_a":"#3a3157","tile_b":"#463b68","goal":"#f2b705"},
]
func _palette() -> Dictionary:
	var tier := int(level_index / TIER_SIZE) % TIER_PALETTES.size()
	return TIER_PALETTES[tier]

func _ready() -> void:
	config = JSON.parse_string(FileAccess.get_file_as_string("res://data/config.json"))
	levels = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels.json"))
	_load_save()
	_setup_audio()
	var base_validation_config := config.duplicate(true)
	base_validation_config.fatigue_enabled = false
	for i in levels.size():
		if not LevelValidator.is_solvable(levels[i], base_validation_config): push_error("Fase-base %d não possui solução estrutural" % (i + 1))
	queue_redraw()

# --- Áudio procedural: sem depender de arquivos externos, geramos pequenos
# tons em memória para cada evento do jogo (coleta, golpe, derrota, vitória).
func _setup_audio() -> void:
	var specs := {
		"pickup": {"freqs":[660.0,880.0,1320.0],"dur":0.09,"vol":-6.0},
		"hit": {"freqs":[220.0,160.0],"dur":0.12,"vol":-4.0},
		"lose": {"freqs":[180.0,120.0],"dur":0.30,"vol":-3.0},
		"win": {"freqs":[523.0,659.0,784.0,1046.0],"dur":0.12,"vol":-5.0},
		"champion": {"freqs":[523.0,659.0,784.0,1046.0,1318.0,1046.0,1318.0],"dur":0.20,"vol":-3.0},
	}
	for key in specs.keys():
		var spec: Dictionary = specs[key]
		var player := AudioStreamPlayer.new()
		player.name = "sfx_%s" % key
		player.stream = _build_arpeggio(spec.freqs, spec.dur)
		player.volume_db = spec.vol
		add_child(player)
		sfx_players[key] = player

func _build_arpeggio(freqs: Array, note_duration: float) -> AudioStreamWAV:
	var mix_rate := 44100
	var data := PackedByteArray()
	for freq in freqs:
		var sample_count := int(mix_rate * note_duration)
		for s in sample_count:
			var envelope := sin(PI * (float(s) / sample_count))
			var value := sin(TAU * float(freq) * (float(s) / mix_rate)) * envelope
			var v16 := int(clampf(value, -1.0, 1.0) * 32767.0)
			data.append(v16 & 0xFF)
			data.append((v16 >> 8) & 0xFF)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = data
	return stream

func _play_sfx(key: String) -> void:
	if not sfx_players.has(key): return
	var player: AudioStreamPlayer = sfx_players[key]
	player.stop(); player.play()

func _haptic(ms: int) -> void:
	Input.vibrate_handheld(ms)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED: queue_redraw()

# Usa a entrada global: no Android, o Control raiz pode deixar de encaminhar
# _gui_input depois que o app perde/recupera o foco no emulador.
func _input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch or event is InputEventMouseButton): return
	if not event.pressed: return
	# Android pode sintetizar MouseButton logo após ScreenTouch para o mesmo toque.
	# Depois de trocar/resetar a tela, consome essa duplicata antes que vire movimento.
	if Time.get_ticks_msec() < input_block_until_ms: return
	var pos: Vector2 = event.position
	if quit_modal:
		if quit_confirm_button.has_point(pos): get_tree().quit()
		elif quit_cancel_button.has_point(pos): quit_modal = false; queue_redraw()
		return
	if close_button.has_point(pos):
		quit_modal = true; queue_redraw()
	elif defeat_modal and retry_button.has_point(pos):
		input_block_until_ms = Time.get_ticks_msec() + 350
		defeat_modal = false; hero_kneeling = false
		_reset_attempt(pending_restart_lives if pending_restart_lives > 0 else int(config.start_lives))
		screen = "game"
	elif screen == "home" and play_button.has_point(pos):
		input_block_until_ms = Time.get_ticks_msec() + 350
		_start_level(unlocked - 1)
	elif screen == "lost" and retry_button.has_point(pos):
		input_block_until_ms = Time.get_ticks_msec() + 350
		_reset_attempt(int(config.start_lives))
		screen = "game"
	elif screen == "congratulations" and retry_button.has_point(pos):
		input_block_until_ms = Time.get_ticks_msec() + 350
		unlocked = 1
		_save()
		screen = "home"
	elif screen == "game" and not hero_kneeling:
		var cell := Vector2i(floor((pos.x - board_rect.position.x) / tile_size), floor((pos.y - board_rect.position.y) / tile_size))
		if abs(cell.x - player.x) + abs(cell.y - player.y) == 1: _try_move(cell)

func _start_level(index: int) -> void:
	# Mostra a barra de carregamento JÁ no toque, antes de qualquer cálculo —
	# assim a tela nunca fica parada sem explicação enquanto a fase é gerada.
	loading_progress = 0.0
	screen = "loading"
	queue_redraw()
	await get_tree().process_frame
	level_index = clampi(index, 0, MAX_STAGE - 1)
	if level_index < levels.size():
		level = levels[level_index].duplicate(true)
	else:
		# Depois das oito fases introdutórias, reutiliza a maior malha como base
		# e deixa o gerador procedural criar um desafio novo para cada número.
		level = levels[-1].duplicate(true)
		level.name = "Desafio procedural"
		if level_index == MAX_STAGE - 1:
			# A última fase tem exatamente 100 casas. Com dez linhas, a rota
			# serpente termina no canto superior esquerdo.
			level.width = 10
			level.height = 10
			level.start = [0,9]
			level.goal = [0,0]
			# Âncoras distribuídas pela rota mantêm itens possíveis por toda a grade.
			level.items = [
				{"p":[1,9],"type":"plus1"}, {"p":[8,8],"type":"sword"},
				{"p":[2,7],"type":"helmet"}, {"p":[7,6],"type":"crown"},
				{"p":[3,5],"type":"double"}, {"p":[6,4],"type":"shield"},
				{"p":[4,3],"type":"armor"}, {"p":[5,2],"type":"staff"},
				{"p":[5,1],"type":"boots"}
			]
			level.enemies = []
	await _prepare_level_contents()
	loading_progress = 1.0
	player = Vector2i(level.start[0], level.start[1])
	power = int(config.start_power); lives = int(config.start_lives)
	pending_restart_lives = lives
	fatigue_chain = 0
	collected.clear(); defeated.clear(); revealed_bosses.clear(); hero_kneeling = false; defeat_modal = false; pickup_active = false; pickup_item_index = -1; equipment = {"weapons":[], "head":"", "helmet":false, "crown":false, "shield":false, "armor":false, "cape":false, "boots":false, "amulet":false}
	screen = "game"
	if (level_index + 1) % MILESTONE_STEP == 0:
		feedback = "MARCO! FASE %d" % (level_index + 1)
		_play_sfx("win"); _haptic(120)
	else:
		feedback = "TOQUE NUMA CASA AO LADO"
	feedback_alpha = 1.0
	queue_redraw()

func _prepare_level_contents() -> void:
	var goal_pos := Vector2i(level.goal[0], level.goal[1])
	var start_pos := Vector2i(level.start[0], level.start[1])
	var enemies: Array = level.get("enemies", [])
	for i in range(enemies.size()-1, -1, -1):
		var enemy: Dictionary = enemies[i]
		if Vector2i(enemy.p[0], enemy.p[1]) == goal_pos: enemies.remove_at(i)
	var occupied := {start_pos:true, goal_pos:true}
	var enemy_cells: Array[Vector2i] = []
	for enemy in enemies:
		var enemy_pos := Vector2i(enemy.p[0],enemy.p[1])
		enemy_cells.append(enemy_pos)
		occupied[enemy_pos] = true
	var original_items: Array = level.get("items", [])
	var item_positions: Array[Vector2i] = []
	for item in original_items: item_positions.append(Vector2i(item.p[0],item.p[1]))
	item_positions.sort_custom(func(a:Vector2i,b:Vector2i): return a.distance_squared_to(start_pos) < b.distance_squared_to(start_pos))
	var items: Array = []
	var starter_power := int(config.start_power)
	var growth_anchor := item_positions[0] if not item_positions.is_empty() else start_pos
	# Fases sem nenhum item na base (não deveria acontecer com os dados atuais, mas
	# uma fase futura mal configurada não pode derrubar o jogo por acessar índice vazio).
	if not item_positions.is_empty():
		var growth_types := ["plus1","sword","helmet","crown","double","axe","spear","hammer","shield","armor","cape","boots","amulet","staff"]
		var growth_type: String = growth_types.pick_random()
		var growth_item := {"p":[growth_anchor.x,growth_anchor.y],"type":growth_type,"generated":true}
		if growth_type == "plus1":
			var potion_max := maxi(2,(level_index+1)*7)
			growth_item.power = randi_range(maxi(1,int(potion_max/3)),potion_max)
		items.append(growth_item)
		var extra_count := randi_range(0, mini(item_positions.size()-1, maxi(0,int(level_index/2))))
		var all_item_types := ["plus1","sword","helmet","crown","heart","double","axe","spear","hammer","shield","armor","cape","boots","amulet","staff"]
		for i in range(1,1+extra_count):
			var item_type: String = all_item_types.pick_random()
			var pos := item_positions[i]
			var extra_item := {"p":[pos.x,pos.y],"type":item_type,"generated":true}
			if item_type == "plus1":
				var potion_max := maxi(2,(level_index+1)*7)
				extra_item.power = randi_range(maxi(1,int(potion_max/3)),potion_max)
			items.append(extra_item)
		var growth_cfg: Dictionary = config.items[growth_type]
		starter_power = int(config.start_power)*int(growth_cfg.get("multiply",1))+int(growth_item.get("power",growth_cfg.get("power",0)))
	for item in items: occupied[Vector2i(item.p[0],item.p[1])] = true
	var empty_cells: Array[Vector2i] = []
	for y in int(level.height):
		for x in int(level.width):
			var cell := Vector2i(x,y)
			if not occupied.has(cell):
				empty_cells.append(cell)
				enemy_cells.append(cell)
	level.items = items
	# Fases procedurais grandes (além das 8 fases-base) usam a mesma construção
	# garantida por caminhada aleatória de baixo — antes usavam uma serpente
	# fixa fileira-por-fileira própria, o que voltava a parecer um "caracol"
	# mecânico justamente nas fases 9+.
	if level_index >= levels.size():
		_build_bfs_guaranteed_enemies(start_pos, goal_pos, enemy_cells)
		return
	# REGRA Nº 1: nunca entregar uma fase impossível. Com poucos inimigos o
	# LevelValidator confirma exaustivamente (rápido e correto). Só que com
	# ~11+ inimigos o espaço de busca já passa de 2^11 combinações — o teto de
	# segurança do validador faz ele "desistir" achando que não dá pra
	# resolver, mesmo quando dá. Isso podia gerar fases que PARECEM ok (o
	# validador não achou nada de errado dentro do teto) mas na real dependiam
	# de sorte. Fases desse tamanho vão direto pra construção garantida por
	# BFS abaixo, que é vencível por construção — sem depender do validador.
	if enemy_cells.size() > 10:
		_build_bfs_guaranteed_enemies(start_pos, goal_pos, enemy_cells)
		return
	for attempt in 64:
		# Progresso real da barra de carregamento: uma tentativa falhando não
		# trava mais nada, só avança a barra e tenta de novo no próximo frame.
		loading_progress = float(attempt) / 64.0
		queue_redraw()
		await get_tree().process_frame
		enemies = []
		enemy_cells.shuffle()
		var available_power := starter_power
		for cell in enemy_cells:
			var low := maxi(1, int(available_power*.28))
			var high := maxi(low, available_power-1)
			var enemy_power := randi_range(low, high)
			enemies.append({"p":[cell.x,cell.y],"power":enemy_power,"generated":true})
			available_power += enemy_power
		var boss_power := _highest_solvable_boss(enemies,goal_pos)
		if boss_power < 1: continue
		enemies.append({"p":[goal_pos.x,goal_pos.y],"power":boss_power,"boss":true})
		level.enemies = enemies
		return
	# Nunca deveria chegar aqui com enemy_cells.size() <= 10 (o validador exato
	# dá conta), mas por segurança use a mesma construção garantida em vez de
	# arriscar uma fase ruim.
	_build_bfs_guaranteed_enemies(start_pos, goal_pos, enemy_cells)

func _random_walk_path(start_pos: Vector2i, goal_pos: Vector2i, w: int, h: int) -> Array[Vector2i]:
	# Caminhada aleatória de verdade (não fileira por fileira): em cada casa,
	# sorteia entre os vizinhos ainda não visitados. Quando não sobra vizinho
	# livre, "emenda" pelo caminho mais curto até o objetivo — garante que
	# sempre termina no lugar certo, mesmo sem ter coberto o tabuleiro
	# inteiro (a caminhada aleatória cobre o máximo que der organicamente).
	var directions := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	var visited := {start_pos: true}
	var path: Array[Vector2i] = [start_pos]
	while true:
		var current: Vector2i = path[-1]
		var options: Array[Vector2i] = []
		for d in directions:
			var n: Vector2i = current + d
			if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h: continue
			if visited.has(n): continue
			options.append(n)
		if options.is_empty(): break
		options.shuffle()
		visited[options[0]] = true
		path.append(options[0])
	if path[-1] != goal_pos:
		var came_from := {path[-1]: path[-1]}
		var queue: Array[Vector2i] = [path[-1]]
		var head := 0
		while head < queue.size():
			var cur: Vector2i = queue[head]; head += 1
			if cur == goal_pos: break
			for d in directions:
				var n: Vector2i = cur + d
				if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h: continue
				if came_from.has(n): continue
				came_from[n] = cur
				queue.append(n)
		var tail: Array[Vector2i] = [goal_pos]
		while tail[-1] != path[-1]:
			tail.append(came_from[tail[-1]])
		tail.reverse()
		path.append_array(tail.slice(1))
	return path

func _build_bfs_guaranteed_enemies(start_pos: Vector2i, goal_pos: Vector2i, enemy_cells: Array[Vector2i]) -> void:
	# Caminho ALEATÓRIO cobrindo o máximo de casas possível do tabuleiro — a
	# versão anterior era sempre fileira por fileira (um "caracol" mecânico e
	# previsível), agora é uma caminhada de verdade, diferente a cada fase.
	var enemy_set := {}
	for cell in enemy_cells: enemy_set[cell] = true
	var item_by_cell := {}
	for item in level.items: item_by_cell[Vector2i(item.p[0],item.p[1])] = item
	var path := _random_walk_path(start_pos, goal_pos, int(level.width), int(level.height))
	# Poder BASE de verdade, sem inflar nada. O piso do inimigo (e do chefão)
	# é 0, não 1: com poder base 1, 1 > 0 sempre vence, então mesmo o primeiro
	# inimigo do caminho — antes de qualquer item — nunca trava o herói.
	var route_power := int(config.start_power)
	var enemies: Array = []
	var boss_power := 1
	var processed := {start_pos: true}
	for cell in path:
		if processed.has(cell): continue
		processed[cell] = true
		if cell == goal_pos:
			boss_power = maxi(0, route_power-1)
		elif item_by_cell.has(cell):
			var item: Dictionary = item_by_cell[cell]
			var item_cfg: Dictionary = config.items[item.type]
			route_power = route_power*int(item.get("multiply",item_cfg.get("multiply",1)))+int(item.get("power",item_cfg.get("power",0)))
		elif enemy_set.has(cell):
			var enemy_power := clampi(int(route_power*.5), 0, route_power-1)
			enemies.append({"p":[cell.x,cell.y],"power":enemy_power,"generated":true})
			route_power += enemy_power
	# Quem ficou fora do caminho (a caminhada aleatória às vezes não cobre 100%
	# do tabuleiro) não precisa ser vencível, mas ganha poder generoso.
	for cell in enemy_cells:
		if processed.has(cell): continue
		var enemy_power := maxi(1, int(route_power*randf_range(.2,.6)))
		enemies.append({"p":[cell.x,cell.y],"power":enemy_power,"generated":true})
	enemies.append({"p":[goal_pos.x,goal_pos.y],"power":boss_power,"boss":true})
	level.enemies = enemies

func _highest_solvable_boss(enemies: Array, goal_pos: Vector2i) -> int:
	var low := 0
	var high := _total_boss_power(enemies)
	var best := -1
	while low <= high:
		var middle := int((low+high)/2)
		var candidate := enemies.duplicate(true)
		candidate.append({"p":[goal_pos.x,goal_pos.y],"power":middle,"boss":true})
		level.enemies = candidate
		if LevelValidator.is_solvable(level,config):
			best = middle
			low = middle+1
		else: high = middle-1
	return best

func _total_boss_power(enemies: Array) -> int:
	var additive := int(config.start_power)
	var multiplier := 1
	for item in level.get("items", []):
		var item_cfg: Dictionary = config.items[item.type]
		additive += int(item.get("power", item_cfg.get("power", 0)))
		multiplier *= int(item_cfg.get("multiply", 1))
	for enemy in enemies: additive += int(enemy.power)
	return maxi(1, additive * multiplier - 1)

func _try_move(target: Vector2i) -> void:
	if combat_active or pickup_active or hero_kneeling or walk_move_active: return
	if target.x < 0 or target.y < 0 or target.x >= int(level.width) or target.y >= int(level.height): return
	move_direction = target - player
	var had_content := _cell_has_content(target)
	for i in range(level.get("enemies", []).size()):
		var enemy: Dictionary = level.enemies[i]
		if not defeated.has(i) and target == Vector2i(enemy.p[0], enemy.p[1]):
			if bool(enemy.get("boss", false)): revealed_bosses[i] = true
			combat_active = true; combat_target = target; combat_time = COMBAT_DURATION
			await get_tree().create_timer(COMBAT_DURATION).timeout
			if power <= int(enemy.power):
				lives -= 1
				feedback = "ESCOLHA OUTRO CAMINHO" if bool(enemy.get("boss", false)) else "FORTE DEMAIS! -1 VIDA"
				feedback_alpha = 1.0; shake = 1.0
				combat_active = false
				_play_sfx("lose"); _haptic(150)
				if bool(enemy.get("boss", false)) or lives <= 0 or _no_progress_possible():
					await _trigger_no_chance(true)
				queue_redraw(); return
			enemy_defeat_target = target; enemy_defeat_time = DEFEAT_DURATION
			_play_sfx("hit"); _haptic(40)
			await get_tree().create_timer(DEFEAT_DURATION).timeout
			combat_active = false; enemy_defeat_target = Vector2i(-1,-1); defeated[i] = true; power += int(enemy.power); feedback = "+%d PODER" % int(enemy.power); feedback_alpha = 1.0
	var item_index := _item_index_at(target)
	if item_index >= 0:
		await _animate_item_pickup(target,item_index)
	else:
		# Antes o herói "teleportava" para qualquer casa livre (só a aproximação de
		# combate/coleta era animada). Isso é bem comum ao recuar por uma casa já
		# limpa, então agora anda de verdade até lá também.
		await _animate_walk(target)
	if had_content:
		fatigue_chain = 0
	else:
		var fatigue_cost := 1 << mini(fatigue_chain,20)
		fatigue_chain = mini(fatigue_chain+1,20)
		power = maxi(1,power-fatigue_cost)
		feedback = "CANSAÇO -%d" % fatigue_cost; feedback_alpha = 1.0
	if target == Vector2i(level.goal[0], level.goal[1]): _win()
	elif _no_progress_possible(): await _trigger_no_chance(false)
	queue_redraw()

# Antes, o jogo só olhava se todo inimigo visível tinha poder >= o do herói,
# ignorando itens ainda não coletados que poderiam salvar a tentativa — isso
# derrubava vidas do jogador de forma injusta. Agora: com poucos inimigos e
# itens restantes, reaproveita a busca exata do LevelValidator (instantânea).
# Em fases procedurais enormes (dezenas de inimigos), essa busca exata
# explodiria combinatoriamente, então usamos uma aproximação por alcance que
# nunca acusa "sem chance" indevidamente (ela só erra a favor do jogador).
func _no_progress_possible() -> bool:
	if player == Vector2i(level.goal[0], level.goal[1]): return false
	var remaining_enemies := 0
	for i in range(level.get("enemies", []).size()):
		if not defeated.has(i): remaining_enemies += 1
	var remaining_items := 0
	for i in range(level.get("items", []).size()):
		if not collected.has(i): remaining_items += 1
	if remaining_enemies + remaining_items <= 18:
		return not _has_solution_from_current()
	return not _reachable_with_growing_power()

# Alcança, a partir da posição atual, todas as casas atingíveis conforme o
# poder cresce ao longo do caminho (itens e inimigos vencidos aumentam o
# poder, nunca diminuem aqui — a fadiga é ignorada de propósito, pois só
# reduziria o alcance real e poderia gerar falso positivo).
func _reachable_with_growing_power() -> bool:
	var goal_pos := Vector2i(level.goal[0], level.goal[1])
	var enemy_by_cell := {}
	for i in range(level.get("enemies", []).size()):
		if defeated.has(i): continue
		var e: Dictionary = level.enemies[i]
		enemy_by_cell[Vector2i(e.p[0], e.p[1])] = i
	var current_power := power
	var visited := {player: true}
	var absorbed_items := {}
	# FALTAVA ISTO: uma casa só entra em "visited" depois de já confirmado que
	# dá pra vencer o inimigo dela (ver o "continue" mais abaixo) — só que o
	# poder ganho ao vencer nunca era somado ao current_power, só o de itens.
	# Isso fazia o jogo achar que a rota tinha travado mesmo quando ela seguia
	# perfeitamente vencível derrotando inimigo atrás de inimigo (exatamente
	# como as fases são desenhadas). Agora conta o poder dos dois.
	var absorbed_enemies := {}
	var changed := true
	while changed:
		changed = false
		for cell in visited.keys():
			var item_index := _item_index_at(cell)
			if item_index >= 0 and not absorbed_items.has(item_index):
				absorbed_items[item_index] = true
				var item: Dictionary = level.items[item_index]
				var cfg: Dictionary = config.items[item.type]
				current_power = current_power * int(item.get("multiply", cfg.get("multiply", 1))) + int(item.get("power", cfg.get("power", 0)))
				changed = true
			if enemy_by_cell.has(cell) and not absorbed_enemies.has(cell):
				absorbed_enemies[cell] = true
				current_power += int(level.enemies[enemy_by_cell[cell]].power)
				changed = true
		for cell in visited.keys():
			for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				var p: Vector2i = cell + d
				if p.x < 0 or p.y < 0 or p.x >= int(level.width) or p.y >= int(level.height): continue
				if visited.has(p): continue
				if enemy_by_cell.has(p) and current_power <= int(level.enemies[enemy_by_cell[p]].power): continue
				visited[p] = true
				changed = true
	return visited.has(goal_pos)

func _item_index_at(pos: Vector2i) -> int:
	for i in range(level.get("items", []).size()):
		var item: Dictionary = level.items[i]
		if not collected.has(i) and pos == Vector2i(item.p[0],item.p[1]): return i
	return -1

func _animate_item_pickup(target: Vector2i, item_index: int) -> void:
	pickup_active = true; pickup_target = target; pickup_item_index = item_index
	pickup_time = PICKUP_MOVE_DURATION+PICKUP_LIFT_DURATION
	await get_tree().create_timer(PICKUP_MOVE_DURATION).timeout
	player = target
	await get_tree().create_timer(PICKUP_LIFT_DURATION).timeout
	_collect(item_index,level.items[item_index])
	pickup_active = false; pickup_item_index = -1; pickup_time = 0.0
	player_bounce = 1.0

func _animate_walk(target: Vector2i) -> void:
	walk_move_active = true; walk_move_from = player; walk_move_to = target; walk_move_time = WALK_MOVE_DURATION
	await get_tree().create_timer(WALK_MOVE_DURATION).timeout
	player = target
	walk_move_active = false; walk_move_time = 0.0
	player_bounce = .6

func _trigger_no_chance(heart_already_lost: bool) -> void:
	if hero_kneeling or defeat_modal: return
	if not heart_already_lost:
		lives = maxi(0,lives-1)
		_play_sfx("lose"); _haptic(150)
	pending_restart_lives = lives
	hero_kneeling = true
	feedback = "ESCOLHA OUTRO CAMINHO"; feedback_alpha = 1.0
	await get_tree().create_timer(.75).timeout
	defeat_modal = true
	queue_redraw()

func _cell_has_content(pos: Vector2i) -> bool:
	for i in range(level.get("enemies", []).size()):
		var enemy: Dictionary = level.enemies[i]
		if not defeated.has(i) and pos == Vector2i(enemy.p[0],enemy.p[1]): return true
	for i in range(level.get("items", []).size()):
		var item: Dictionary = level.items[i]
		if not collected.has(i) and pos == Vector2i(item.p[0],item.p[1]): return true
	return false

func _has_solution_from_current() -> bool:
	var remaining_enemies: Array = []
	for i in range(level.get("enemies", []).size()):
		if not defeated.has(i): remaining_enemies.append(level.enemies[i].duplicate(true))
	var remaining_items: Array = []
	for i in range(level.get("items", []).size()):
		if not collected.has(i): remaining_items.append(level.items[i].duplicate(true))
	var current_level := level.duplicate(true)
	current_level.start = [player.x,player.y]
	current_level.enemies = remaining_enemies
	current_level.items = remaining_items
	var current_config := config.duplicate(true)
	current_config.start_power = power
	current_config.start_fatigue = fatigue_chain
	return LevelValidator.is_solvable(current_level,current_config)

func _reset_attempt(remaining_lives: int) -> void:
	player = Vector2i(level.start[0],level.start[1])
	power = int(config.start_power); lives = remaining_lives; fatigue_chain = 0
	pending_restart_lives = lives
	collected.clear(); defeated.clear(); revealed_bosses.clear()
	hero_kneeling = false; defeat_modal = false; pickup_active = false; pickup_item_index = -1; pickup_time = 0.0
	equipment = {"weapons":[], "head":"", "helmet":false, "crown":false, "shield":false, "armor":false, "cape":false, "boots":false, "amulet":false}
	feedback = "TENTE OUTRA ROTA"; feedback_alpha = 1.0

func _collect(i: int, item: Dictionary) -> void:
	collected[i] = true
	var cfg: Dictionary = config.items[item.type]
	var old := power
	var item_power := int(item.get("power", cfg.get("power", 0)))
	power = power * int(item.get("multiply", cfg.get("multiply", 1))) + item_power
	lives = mini(int(config.max_lives), lives + int(cfg.get("lives", 0)))
	feedback = "%d x 2 = %d" % [old, power] if item.type == "double" else ("+%d" % item_power if item_power > 0 else str(cfg.label))
	feedback_alpha = 1.0
	_play_sfx("pickup")
	if item.type in ["sword","axe","spear","hammer","staff"]:
		if item.type in equipment.weapons: equipment.weapons.erase(item.type)
		equipment.weapons.append(item.type)
	if item.type in ["helmet", "crown"]:
		equipment.head = item.type
		equipment[item.type] = true
	if item.type in ["shield","armor","cape","boots","amulet"]: equipment[item.type] = true

func _win() -> void:
	if level_index + 1 >= MAX_STAGE:
		feedback = "PARABÉNS!"; feedback_alpha = 1.0
		_play_sfx("champion"); _haptic(250)
		await get_tree().create_timer(0.9).timeout
		screen = "congratulations"
		queue_redraw()
		return
	unlocked = mini(MAX_STAGE, maxi(unlocked, level_index + 2)); _save()
	feedback = "FASE CONCLUÍDA!"; feedback_alpha = 1.0
	_play_sfx("win"); _haptic(80)
	await get_tree().create_timer(0.9).timeout
	screen = "home"; queue_redraw()

func _process(delta: float) -> void:
	if combat_time > 0: combat_time = maxf(0, combat_time-delta)
	if pickup_time > 0: pickup_time = maxf(0,pickup_time-delta)
	if walk_move_time > 0: walk_move_time = maxf(0,walk_move_time-delta)
	if enemy_defeat_time > 0: enemy_defeat_time = maxf(0,enemy_defeat_time-delta)
	if hero_defeat_time > 0: hero_defeat_time = maxf(0,hero_defeat_time-delta)
	if player_bounce > 0: player_bounce = maxf(0, player_bounce - delta * 4)
	if shake > 0: shake = maxf(0, shake - delta * 5)
	if feedback_alpha > 0: feedback_alpha = maxf(0, feedback_alpha - delta * 0.55)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(_palette().bg))
	if screen == "home": _draw_home()
	elif screen == "lost": _draw_lost()
	elif screen == "congratulations": _draw_congratulations()
	elif screen == "loading": _draw_loading()
	else: _draw_game()
	_draw_close_button()
	if quit_modal: _draw_quit_modal()

func _draw_quit_modal() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color(0.10,0.07,0.14,.58))
	var panel := Rect2(size.x*.12,size.y*.38,size.x*.76,size.y*.24)
	_round_rect(panel,Color("#fff7e8"),28)
	_center_text("SAIR DO JOGO?",panel.position.y+58,30,Color("#51446b"))
	var gap := 16.0
	var btn_w := (panel.size.x-gap*3)/2.0
	quit_cancel_button = Rect2(panel.position.x+gap,panel.end.y-90,btn_w,64)
	quit_confirm_button = Rect2(quit_cancel_button.end.x+gap,panel.end.y-90,btn_w,64)
	_round_rect(quit_cancel_button,Color("#e6d9cc"),16)
	_center_on("VOLTAR",quit_cancel_button.get_center().x,quit_cancel_button.get_center().y+9,24,Color("#51446b"))
	_round_rect(quit_confirm_button,Color("#d84d63"),16)
	_center_on("SAIR",quit_confirm_button.get_center().x,quit_confirm_button.get_center().y+9,24,Color.WHITE)

func _draw_close_button() -> void:
	close_button = Rect2(size.x-72, 24, 52, 52)
	_round_rect(close_button, Color("#e6d9cc"), 15)
	var center := close_button.get_center()
	draw_line(center-Vector2(10,10), center+Vector2(10,10), Color("#594c65"), 5, true)
	draw_line(center+Vector2(-10,10), center+Vector2(10,-10), Color("#594c65"), 5, true)

func _draw_home() -> void:
	var landscape := size.x > size.y
	var title_y := 92.0 if landscape else size.y*.145
	var hero_y := size.y*.39 if landscape else size.y*.305
	var phase_y := size.y*.56 if landscape else size.y*.435
	var button_y := size.y*.62 if landscape else size.y*.485
	var button_h := minf(112.0,size.y*.14)
	_center_text("CAMINHO DO PODER",title_y,42 if landscape else 48,Color("#362b52"))
	_center_text("Escolha a rota. Fique mais forte.",title_y+48,21,Color("#756a88"))
	_draw_hero(Vector2(size.x/2,hero_y),1.0 if landscape else 1.25)
	_center_text("FASE %d" % unlocked,phase_y,30,Color("#6957a5"))
	play_button = Rect2(size.x*.20 if landscape else size.x*.16,button_y,size.x*.60 if landscape else size.x*.68,button_h)
	_round_rect(play_button,Color("#7057d9"),28)
	_center_text("JOGAR",button_y+button_h*.66,36,Color.WHITE)
	_center_text("Toque nas casas vizinhas para andar",button_y+button_h+42,20,Color("#8b8095"))

func _draw_lost() -> void:
	var title_y := size.y*.30
	_center_text("TENTE NOVAMENTE",title_y,46,Color("#d84d63"))
	_center_text("A fase %d recomeça do início" % (level_index+1),title_y+55,23,Color("#756a88"))
	retry_button = Rect2(size.x*.18,size.y*.48,size.x*.64,minf(112.0,size.y*.16))
	_round_rect(retry_button,Color("#7057d9"),28)
	_center_text("REINICIAR",retry_button.position.y+retry_button.size.y*.66,34,Color.WHITE)

func _draw_loading() -> void:
	# Aparece assim que o jogador toca em JOGAR, antes de qualquer cálculo da
	# fase — a barra enche com o progresso real da geração (ver _start_level /
	# _prepare_level_contents), então a tela nunca fica parada sem explicação.
	_center_text("PREPARANDO A FASE...",size.y*.44,28,Color("#51446b"))
	var bar := Rect2(size.x*.16,size.y*.50,size.x*.68,26)
	_round_rect(bar,Color("#e6d9cc"),13)
	var fill := bar
	fill.size.x = bar.size.x*clampf(loading_progress,0.0,1.0)
	if fill.size.x > 4: _round_rect(fill,Color("#7057d9"),13)
	_draw_hero(Vector2(size.x/2,size.y*.30),1.0)

func _draw_congratulations() -> void:
	# Confete caindo continuamente: celebração visível assim que o jogador
	# termina a fase 999, sem precisar de nenhum asset externo.
	var t := Time.get_ticks_msec()*.001
	var confetti_colors := [Color("#7057d9"),Color("#f2b705"),Color("#62c9a5"),Color("#d84d63"),Color("#4b9bd8")]
	for i in 24:
		var lane := float(i)*2.399963
		var x := size.x*.5+cos(lane*3.1+t*.6)*size.x*.42
		var y := fmod(t*46.0+float(i)*41.0, size.y+40.0)-20.0
		draw_circle(Vector2(x,y), 5.0+float(i%3)*2.0, confetti_colors[i%confetti_colors.size()])
	var title_y := size.y*.22
	var crown_rect := Rect2(Vector2(size.x/2-46,title_y-118),Vector2(92,72))
	_draw_atlas_cell(Vector2i(1,1),crown_rect,65.0)
	_center_text("VOCÊ É CAMPEÃO!",title_y,52,Color("#7057d9"))
	_center_text("999 FASES CONCLUÍDAS",title_y+68,26,Color("#51446b"))
	_center_text("O CAMINHO DO PODER RECOMEÇARÁ",title_y+108,20,Color("#756a88"))
	retry_button = Rect2(size.x*.18,size.y*.58,size.x*.64,minf(112.0,size.y*.16))
	_round_rect(retry_button,Color("#7057d9"),28)
	_center_text("RECOMEÇAR",retry_button.position.y+retry_button.size.y*.66,34,Color.WHITE)

func _draw_ambient(palette: Dictionary) -> void:
	# Partículas lentas típicas do "bioma" da fase — ficam encobertas pelo tabuleiro
	# na maior parte da tela e só aparecem nas margens, então não atrapalham a leitura.
	var accent: Color = Color(palette.goal)
	var t := Time.get_ticks_msec()*.001
	for i in 14:
		var seed_a := float(i)*1.913
		var x := fmod(seed_a*137.0+t*18.0, size.x)
		var y := fmod(seed_a*251.0+t*11.0, size.y)
		draw_circle(Vector2(x,y), 2.5+float(i%3), Color(accent.r,accent.g,accent.b,.16))

func _draw_game() -> void:
	_center_text("FASE %d  •  %s" % [level_index+1, level.name], 60, 24, Color("#51446b"))
	_center_text("⚔  %d" % power, 113, 38, Color("#44345f"))
	_center_text("♥ ".repeat(lives), 156, 31, Color("#e94f64"))
	var landscape := size.x > size.y
	var board_top := 190.0 if landscape else 205.0
	var board_bottom_margin := 72.0 if landscape else 80.0
	var available_w := size.x - 48.0
	var available_h := size.y - board_top - board_bottom_margin
	tile_size = minf(minf(available_w / int(level.width), available_h / int(level.height)), 210.0)
	var bs := Vector2(tile_size * int(level.width), tile_size * int(level.height))
	board_rect = Rect2(Vector2((size.x-bs.x)/2, board_top + (available_h-bs.y)/2), bs)
	var palette := _palette()
	_draw_ambient(palette)
	for y in int(level.height):
		for x in int(level.width):
			var r := Rect2(board_rect.position + Vector2(x,y)*tile_size + Vector2(4,4), Vector2.ONE*(tile_size-8))
			_round_rect(r, Color(palette.tile_b) if (x+y)%2 else Color(palette.tile_a), tile_size*.14)
	# Anel pulsante sob o herói: ajuda a "ancorar" o personagem na casa atual.
	var accent: Color = Color(palette.goal)
	var anchor_pulse := .85+sin(Time.get_ticks_msec()*.004)*.15
	draw_arc(_cell_center(player), tile_size*.40*anchor_pulse, 0, TAU, 24, Color(accent.r,accent.g,accent.b,.28), tile_size*.03, true)
	var g := Vector2i(level.goal[0], level.goal[1]); var gc := _cell_center(g)
	var goal_pulse := 1.0+sin(Time.get_ticks_msec()*.003)*.08
	draw_arc(gc, tile_size*.34*goal_pulse, 0, TAU, 24, Color(accent.r,accent.g,accent.b,.4), tile_size*.045, true)
	draw_circle(gc, tile_size*.25*goal_pulse, accent); _text("★", gc+Vector2(-tile_size*.16,tile_size*.14), int(tile_size*.38), Color.WHITE)
	for i in range(level.get("items", []).size()):
		if not collected.has(i) and not (pickup_active and i == pickup_item_index): _draw_item(level.items[i])
	for i in range(level.get("enemies", []).size()):
		if not defeated.has(i):
			var enemy: Dictionary = level.enemies[i]
			_draw_enemy(enemy, not bool(enemy.get("boss", false)) or revealed_bosses.has(i))
	var jitter := Vector2(sin(Time.get_ticks_msec()*.04)*shake*9, 0)
	var combat_offset := Vector2.ZERO
	var walk_phase := 0.0
	var is_walking := false
	if combat_active:
		var progress := 1.0-combat_time/COMBAT_DURATION
		var direction := _cell_center(combat_target)-_cell_center(player)
		if progress < .68:
			# Caminha de corpo inteiro e para diante do adversário.
			combat_offset = direction * (smoothstep(0.0,.68,progress)*.58)
			is_walking = true
			walk_phase = progress/.68*TAU*3.0
		else:
			# Avança a arma e volta à posição de combate antes do resultado.
			var strike := sin(((progress-.68)/.32)*PI)
			combat_offset = direction * (.58 + strike*.20)
	elif pickup_active:
		var pickup_elapsed := PICKUP_MOVE_DURATION+PICKUP_LIFT_DURATION-pickup_time
		if pickup_elapsed < PICKUP_MOVE_DURATION:
			var pickup_progress := clampf(pickup_elapsed/PICKUP_MOVE_DURATION,0.0,1.0)
			var pickup_direction := _cell_center(pickup_target)-_cell_center(player)
			combat_offset = pickup_direction*smoothstep(0.0,1.0,pickup_progress)
			is_walking = true
			walk_phase = pickup_progress*TAU*1.5
		else:
			# Para completamente, abaixa para pegar e volta a se erguer.
			var lift_progress := clampf((pickup_elapsed-PICKUP_MOVE_DURATION)/PICKUP_LIFT_DURATION,0.0,1.0)
			var crouch := sin(clampf(lift_progress/.55,0.0,1.0)*PI)
			combat_offset += Vector2(0,crouch*tile_size*.055)
	elif walk_move_active:
		# Movimento comum (inclusive recuar por uma casa já limpa) agora também
		# anda de verdade em vez de teleportar direto para o destino.
		var walk_progress := clampf(1.0-walk_move_time/WALK_MOVE_DURATION,0.0,1.0)
		var walk_direction := _cell_center(walk_move_to)-_cell_center(walk_move_from)
		combat_offset = walk_direction*smoothstep(0.0,1.0,walk_progress)
		is_walking = true
		walk_phase = walk_progress*TAU*1.5
	var defeat_drop := Vector2(0,(.65-hero_defeat_time)*tile_size*.35) if hero_defeat_time > 0 else Vector2.ZERO
	var walk_bob := Vector2(sin(walk_phase)*tile_size*.025,-abs(sin(walk_phase))*tile_size*.065) if is_walking else Vector2.ZERO
	var hero_center := _cell_center(player)+jitter+combat_offset+defeat_drop+walk_bob+Vector2(0,-sin(player_bounce*PI)*tile_size*.18)
	if hero_kneeling: hero_center += Vector2(0,tile_size*.17)
	var side_view := combat_active or pickup_active or walk_move_active or (player_bounce > 0.0 and move_direction.x != 0)
	var faces_left := move_direction.x < 0
	if combat_active or pickup_active:
		var facing_target := combat_target if combat_active else pickup_target
		faces_left = facing_target.x < player.x
		if facing_target.x == player.x: faces_left = false
	var active_target := combat_target if combat_active else pickup_target
	var looks_up := (combat_active or pickup_active) and active_target.x == player.x and active_target.y < player.y
	if walk_move_active: looks_up = walk_move_to.x == walk_move_from.x and walk_move_to.y < walk_move_from.y
	var stride := sin(walk_phase) if is_walking else 0.0
	var body_sway: float = stride*.055 if is_walking else 0.0
	var step_squash: float = 1.0-abs(stride)*0.035 if is_walking else 1.0
	if pickup_active and not is_walking:
		var lift_elapsed := PICKUP_MOVE_DURATION+PICKUP_LIFT_DURATION-pickup_time-PICKUP_MOVE_DURATION
		var lift_p := clampf(lift_elapsed/PICKUP_LIFT_DURATION,0.0,1.0)
		step_squash = 1.0-sin(clampf(lift_p/.55,0.0,1.0)*PI)*.10
	if hero_kneeling:
		body_sway = .08
		step_squash = .56
	_draw_hero(hero_center, tile_size/108.0, side_view, faces_left, body_sway, step_squash, looks_up, stride)
	if pickup_active: _draw_lifted_item(hero_center)
	if is_walking:
		var foot_y := hero_center.y+tile_size*.35
		var step_side := 1.0 if sin(walk_phase) >= 0 else -1.0
		draw_line(Vector2(hero_center.x-step_side*tile_size*.05,foot_y),Vector2(hero_center.x-step_side*tile_size*.17,foot_y+tile_size*.035),Color(0.25,0.20,0.28,.42),tile_size*.018,true)
	var hero_label := _format_power(power)
	var hero_font_size := int(tile_size*.16)
	var hero_badge_w := _badge_width(hero_label,hero_font_size,tile_size*.34)
	var hero_badge := Rect2(hero_center+Vector2(-hero_badge_w*.5,tile_size*.31),Vector2(hero_badge_w,tile_size*.18))
	_round_rect(hero_badge,Color("#3d72bd"),tile_size*.055)
	_center_on(hero_label,hero_center.x,hero_center.y+tile_size*.445,hero_font_size,Color.WHITE)
	if combat_active:
		var hit := _cell_center(combat_target); var flash := 1.0-combat_time/COMBAT_DURATION
		if flash > .66:
			var style := _active_attack_style()
			if style == "staff":
				var orb := hero_center.lerp(hit,clampf(flash,0,1)); draw_circle(orb,tile_size*.12,Color("#76d9ff")); draw_circle(orb,tile_size*.055,Color.WHITE)
			elif style == "axe": draw_arc(hit,tile_size*.30,-2.5,.5,20,Color("#fff0a8"),tile_size*.07)
			elif style == "spear": draw_line(hero_center,hit+Vector2(tile_size*.2,0),Color("#eaf4ff"),tile_size*.06,true)
			elif style == "hammer":
				draw_circle(hit,tile_size*.24,Color(1,.72,.2,.28)); draw_arc(hit,tile_size*.28,0,TAU,24,Color("#ffc34d"),tile_size*.055)
			elif style == "shield": draw_arc(hit,tile_size*.27,-PI*.7,PI*.7,20,Color("#68b8ff"),tile_size*.09)
			else:
				draw_line(hit+Vector2(-tile_size*.22,-tile_size*.25),hit+Vector2(tile_size*.18,tile_size*.20),Color("#fff0a8"),tile_size*.055,true)
				draw_line(hit+Vector2(tile_size*.18,-tile_size*.22),hit+Vector2(-tile_size*.18,tile_size*.18),Color.WHITE,tile_size*.035,true)
			if equipment.shield: draw_arc(hero_center,tile_size*.25,0,TAU,20,Color(0.3,.7,1,.55),tile_size*.035)
	if feedback_alpha > 0:
		_center_text(feedback, size.y-62, 25, Color(0.35,0.25,0.55,feedback_alpha))
	if defeat_modal: _draw_defeat_modal()

func _draw_defeat_modal() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color(0.10,0.07,0.14,.58))
	var panel := Rect2(size.x*.10,size.y*.31,size.x*.80,size.y*.31)
	_round_rect(panel,Color("#fff7e8"),28)
	_center_text("ESCOLHA OUTRO CAMINHO",panel.position.y+112,34,Color("#51446b"))
	retry_button = Rect2(panel.position.x+panel.size.x*.15,panel.end.y-95,panel.size.x*.70,66)
	_round_rect(retry_button,Color("#7057d9"),18)
	_center_on("OK",retry_button.get_center().x,retry_button.get_center().y+12,28,Color.WHITE)

func _draw_hero(c: Vector2, scale: float, side_view := false, faces_left := true, body_rotation := 0.0, body_squash := 1.0, looks_up := false, walk_stride := 0.0) -> void:
	var extent := 42.0 * scale
	var is_side := side_view and move_direction.x != 0
	var horizontal_flip := -1.0 if is_side and not faces_left else 1.0
	draw_set_transform(c, body_rotation, Vector2(horizontal_flip, body_squash))
	c = Vector2.ZERO
	var body_rect := Rect2(c - Vector2(extent, extent), Vector2.ONE * extent * 2.0)
	# De frente/perfil a capa fica atrás do corpo. De costas ela precisa ficar visível por cima.
	if equipment.cape and not looks_up: _draw_worn_cape(c, extent, is_side)
	var weapons: Array = equipment.weapons
	for i in maxi(0,weapons.size()-1):
		# Armas antigas ficam menores e espaçadas em leque nas costas.
		var count := maxi(1,weapons.size()-1)
		var spread_x := (float(i)-float(count-1)*.5)*extent*.20
		var back_rect := Rect2(c+Vector2(spread_x-extent*.18,-extent*.18-absf(spread_x)*.10),Vector2(extent*.36,extent*.72))
		_draw_weapon(weapons[i],back_rect)
	var hero_texture: Texture2D = HERO_BACK_TEXTURE if looks_up else (HERO_SIDE_TEXTURE if is_side else HERO_TEXTURE)
	draw_texture_rect(hero_texture, body_rect, false)
	if absf(walk_stride) > .05:
		_draw_walking_limbs(c,extent,is_side,walk_stride)
	if equipment.cape and looks_up: _draw_worn_cape(c, extent, false)
	if equipment.armor:
		if is_side or looks_up: _draw_worn_armor(c,extent,is_side,looks_up)
		else: _draw_equipment_cell(Vector2i(1,1),Rect2(c+Vector2(-extent*.43,-extent*.08),Vector2(extent*.86,extent*.72)))
	if equipment.boots:
		if is_side or looks_up: _draw_worn_boots(c,extent,is_side,looks_up)
		else: _draw_equipment_cell(Vector2i(0,2),Rect2(c+Vector2(-extent*.43,extent*.45),Vector2(extent*.86,extent*.39)))
	if equipment.amulet and not looks_up:
		var amulet_width := extent*(.22 if is_side else .40)
		_draw_equipment_cell(Vector2i(1,2),Rect2(c+Vector2(-amulet_width*.5,-extent*.02),Vector2(amulet_width,extent*.40)))
	if equipment.shield:
		# Escudo sempre na mão oposta à arma e ancorado ao corpo transformado.
		_draw_worn_shield(c,extent,is_side,looks_up)
	if not weapons.is_empty():
		var weapon_hand := c+Vector2(extent*.38,extent*.42)
		if looks_up: weapon_hand = c+Vector2(-extent*.38,extent*.42)
		elif is_side: weapon_hand = c+Vector2(extent*.34,extent*.31)
		_draw_hero_hand_weapon(str(weapons[-1]),weapon_hand,extent,is_side)
	if bool(equipment.get("helmet",false)) or equipment.head == "helmet":
		var helmet_width := extent*(.78 if is_side else 1.28)
		var head_rect := Rect2(c + Vector2(-helmet_width*.5, -extent*1.08), Vector2(helmet_width, extent*.88))
		_draw_atlas_cell(Vector2i(2, 1), head_rect, 65.0)
	if bool(equipment.get("crown",false)) or equipment.head == "crown":
		var crown_width := extent*(.62 if is_side else .92)
		var crown_y := -extent*(1.30 if bool(equipment.get("helmet",false)) else 1.05)
		var head_rect := Rect2(c + Vector2(-crown_width*.5,crown_y), Vector2(crown_width, extent*.62))
		_draw_atlas_cell(Vector2i(1, 1), head_rect, 65.0)
	draw_set_transform(Vector2.ZERO)

func _draw_walking_limbs(c: Vector2, extent: float, side_view: bool, stride: float) -> void:
	# Passos alternados desenhados sobre a pose-base para eliminar a sensação de deslizamento.
	var hip := c+Vector2(0,extent*.38)
	var spread := extent*(.24 if side_view else .18)
	var front_foot := c+Vector2(spread*stride,extent*(.78-.05*absf(stride)))
	var back_foot := c+Vector2(-spread*stride,extent*(.78+.03*absf(stride)))
	draw_line(hip+Vector2(-extent*.08,0),back_foot,Color("#17171b"),extent*.085,true)
	draw_line(hip+Vector2(extent*.08,0),front_foot,Color("#17171b"),extent*.085,true)
	draw_line(back_foot-Vector2(extent*.06,0),back_foot+Vector2(extent*.11,0),Color("#17171b"),extent*.085,true)
	draw_line(front_foot-Vector2(extent*.06,0),front_foot+Vector2(extent*.11,0),Color("#17171b"),extent*.085,true)
	# Braços balançam no sentido oposto às pernas.
	var shoulder_y := -extent*.02
	for side in [-1.0,1.0]:
		var shoulder := c+Vector2(side*extent*.30,shoulder_y)
		var hand := c+Vector2(side*extent*(.43-.08*stride*side),extent*(.31+.08*stride*side))
		draw_line(shoulder,hand,Color("#17171b"),extent*.07,true)
		draw_circle(hand,extent*.065,Color("#17171b"))

func _draw_back_head(c: Vector2, extent: float, color: Color) -> void:
	var head_center := c+Vector2(0,-extent*.34)
	draw_circle(head_center,extent*.49,Color("#111111"))
	draw_circle(head_center,extent*.43,color)
	# Cabelos vistos por trás deixam clara a direção para cima.
	draw_line(head_center+Vector2(-extent*.16,-extent*.36),head_center+Vector2(-extent*.25,-extent*.58),Color("#111111"),extent*.075,true)
	draw_line(head_center+Vector2(0,-extent*.40),head_center+Vector2(0,-extent*.64),Color("#111111"),extent*.075,true)
	draw_line(head_center+Vector2(extent*.16,-extent*.36),head_center+Vector2(extent*.27,-extent*.57),Color("#111111"),extent*.075,true)

func _draw_worn_cape(c: Vector2, extent: float, side_view := false) -> void:
	# Capa usada fica atrás do corpo: estreita nos ombros e comprida até os pés.
	var cape_shift := Vector2(extent*.20,0) if side_view else Vector2.ZERO
	var points := PackedVector2Array([
		c+cape_shift+Vector2(-extent*.36,-extent*.02),
		c+cape_shift+Vector2(extent*.36,-extent*.02),
		c+cape_shift+Vector2(extent*.50,extent*.86),
		c+cape_shift+Vector2(0,extent*.72),
		c+cape_shift+Vector2(-extent*.50,extent*.86)
	])
	draw_colored_polygon(points,Color("#b91f35"))
	draw_polyline(PackedVector2Array([points[0],points[4],points[3],points[2],points[1]]),Color("#f2b735"),extent*.075,true)
	draw_line(c+Vector2(0,-extent*.10),c+Vector2(0,extent*.68),Color("#e94747"),extent*.08,true)
	draw_circle(c+cape_shift+Vector2(-extent*.29,-extent*.01),extent*.08,Color("#f0b52c"))
	draw_circle(c+cape_shift+Vector2(extent*.29,-extent*.01),extent*.08,Color("#f0b52c"))

func _draw_worn_armor(c: Vector2, extent: float, side_view: bool, back_view: bool) -> void:
	var half_width := extent*(.25 if side_view else .43)
	var shift_x := extent*.08 if side_view else 0.0
	var top := c.y-extent*.02
	var bottom := c.y+extent*.48
	var armor := PackedVector2Array([
		Vector2(c.x+shift_x-half_width,top),Vector2(c.x+shift_x+half_width,top),
		Vector2(c.x+shift_x+half_width*.82,bottom),Vector2(c.x+shift_x-half_width*.82,bottom)
	])
	draw_colored_polygon(armor,Color("#bac4d1"))
	draw_polyline(PackedVector2Array([armor[0],armor[1],armor[2],armor[3],armor[0]]),Color("#30333b"),extent*.055,true)
	draw_line(Vector2(c.x+shift_x-half_width,top+extent*.08),Vector2(c.x+shift_x+half_width,top+extent*.08),Color("#e4ac25"),extent*.065,true)
	if not back_view:
		draw_line(Vector2(c.x+shift_x,top+extent*.08),Vector2(c.x+shift_x,bottom-extent*.05),Color("#7d8794"),extent*.035,true)

func _draw_worn_boots(c: Vector2, extent: float, side_view: bool, _back_view: bool) -> void:
	var boot_color := Color("#6f4028")
	var sole := Color("#2b2424")
	if side_view:
		var boot := Rect2(c+Vector2(-extent*.05,extent*.55),Vector2(extent*.36,extent*.26))
		_round_rect(boot,boot_color,extent*.07)
		draw_line(Vector2(boot.position.x,boot.end.y),Vector2(boot.end.x+extent*.08,boot.end.y),sole,extent*.07,true)
	else:
		for side in [-1.0,1.0]:
			var boot := Rect2(c+Vector2(side*extent*.18-extent*.14,extent*.55),Vector2(extent*.28,extent*.25))
			_round_rect(boot,boot_color,extent*.06)
			draw_line(Vector2(boot.position.x,boot.end.y),Vector2(boot.end.x,boot.end.y),sole,extent*.06,true)

func _draw_worn_shield(c: Vector2, extent: float, side_view: bool, back_view: bool) -> void:
	var hand := c+Vector2(-extent*.38,extent*.42)
	if back_view: hand = c+Vector2(extent*.38,extent*.42)
	elif side_view: hand = c+Vector2(-extent*.30,extent*.30)
	var center := hand+Vector2(0,extent*.10)
	# Broquel redondo (aro, disco azul, umbo e rebites), igual ao ícone do
	# inventário — antes era um polígono pontudo, sem nada a ver com o item.
	var radius := extent*(.26 if side_view else .34)
	draw_circle(center, radius, Color("#c7cfd6"))
	draw_circle(center, radius*.86, Color("#267ac1"))
	draw_circle(center, radius*.30, Color("#aeb8c2"))
	draw_arc(center, radius*.30, 0, TAU, 14, Color("#5b6672"), extent*.02, true)
	for i in 6:
		var rivet := center + Vector2.RIGHT.rotated(i*TAU/6.0) * radius * .70
		draw_circle(rivet, radius*.07, Color("#8b96a3"))
	draw_circle(hand,extent*.075,Color("#17171b"))

func _draw_hero_hand_weapon(type: String, hand: Vector2, extent: float, side_view: bool) -> void:
	# Todas as armas compartilham o mesmo ponto final: o centro da mão.
	var outward := -1.0 if side_view else 1.0
	var top := hand+Vector2(extent*.12*outward,-extent*.66)
	var dark := Color("#25252c")
	var wood := Color("#754225")
	var metal := Color("#e7edf3")
	var gold := Color("#e5a900")
	if type == "sword":
		var guard := hand+Vector2(extent*.03*outward,-extent*.15)
		draw_line(hand,guard,wood,extent*.09,true)
		draw_line(guard+Vector2(-extent*.14,0),guard+Vector2(extent*.14,0),gold,extent*.07,true)
		draw_line(guard,top,dark,extent*.17,true)
		draw_line(guard,top,metal,extent*.11,true)
	elif type == "axe":
		draw_line(hand,top,wood,extent*.085,true)
		var head := PackedVector2Array([top+Vector2(-extent*.18,-extent*.10),top+Vector2(extent*.14,-extent*.08),top+Vector2(extent*.10,extent*.14),top+Vector2(-extent*.14,extent*.09)])
		draw_colored_polygon(head,metal); draw_polyline(PackedVector2Array([head[0],head[1],head[2],head[3],head[0]]),dark,extent*.035,true)
	elif type == "hammer":
		draw_line(hand,top,wood,extent*.09,true)
		var hammer_head := Rect2(top-Vector2(extent*.22,extent*.11),Vector2(extent*.44,extent*.22))
		_round_rect(hammer_head,Color("#77818d"),extent*.04)
	elif type == "staff":
		draw_line(hand,top,wood,extent*.085,true)
		var crystal := top+Vector2(0,-extent*.12)
		draw_colored_polygon(PackedVector2Array([crystal+Vector2(0,-extent*.14),crystal+Vector2(extent*.11,0),crystal+Vector2(0,extent*.14),crystal+Vector2(-extent*.11,0)]),Color("#55c9ff"))
	else: # lança
		draw_line(hand,top,wood,extent*.085,true)
		var tip := top+Vector2(0,-extent*.25)
		var spear := PackedVector2Array([tip,top+Vector2(-extent*.13,0),top+Vector2(0,extent*.08),top+Vector2(extent*.13,0)])
		draw_colored_polygon(spear,metal); draw_polyline(PackedVector2Array([spear[0],spear[1],spear[2],spear[3],spear[0]]),dark,extent*.035,true)
	# A mão por cima do cabo elimina qualquer aparência de item flutuando.
	draw_circle(hand,extent*.075,Color("#17171b"))

func _draw_weapon(type: String, destination: Rect2) -> void:
	if type == "sword": _draw_clean_sword(destination)
	else:
		var cells := {"axe":Vector2i(0,0),"spear":Vector2i(1,0),"hammer":Vector2i(2,0),"staff":Vector2i(2,2)}
		if cells.has(type): _draw_equipment_cell(cells[type],destination)

func _draw_clean_sword(r: Rect2) -> void:
	# Espada equipada sem recorte do atlas: lâmina limpa e cabo exatamente na mão.
	var cx := r.position.x+r.size.x*.5
	var blade := PackedVector2Array([
		Vector2(cx,r.position.y),
		Vector2(r.position.x+r.size.x*.72,r.position.y+r.size.y*.18),
		Vector2(r.position.x+r.size.x*.60,r.position.y+r.size.y*.67),
		Vector2(r.position.x+r.size.x*.40,r.position.y+r.size.y*.67),
		Vector2(r.position.x+r.size.x*.28,r.position.y+r.size.y*.18)
	])
	draw_colored_polygon(blade,Color("#eef3f8"))
	var outline := PackedVector2Array([blade[0],blade[1],blade[2],blade[3],blade[4],blade[0]])
	draw_polyline(outline,Color("#24242b"),maxf(2.0,r.size.x*.07),true)
	draw_line(Vector2(cx,r.position.y+r.size.y*.08),Vector2(cx,r.position.y+r.size.y*.60),Color("#b9c5d3"),maxf(1.0,r.size.x*.035),true)
	var guard_y := r.position.y+r.size.y*.68
	draw_line(Vector2(r.position.x+r.size.x*.25,guard_y),Vector2(r.position.x+r.size.x*.75,guard_y),Color("#e5a900"),maxf(3.0,r.size.x*.12),true)
	draw_line(Vector2(cx,guard_y),Vector2(cx,r.position.y+r.size.y*.91),Color("#6b3d22"),maxf(3.0,r.size.x*.13),true)
	draw_circle(Vector2(cx,r.position.y+r.size.y*.94),r.size.x*.10,Color("#e5a900"))

func _draw_enemy(e: Dictionary, show_power := true) -> void:
	var enemy_pos := Vector2i(e.p[0],e.p[1]); var c := _cell_center(enemy_pos); var is_boss := bool(e.get("boss", false)); var extent := tile_size*(.48 if is_boss else .43)
	if enemy_pos == enemy_defeat_target: c += Vector2(sin(Time.get_ticks_msec()*.06)*tile_size*.08,(DEFEAT_DURATION-enemy_defeat_time)*tile_size*.38)
	var is_dangerous := int(e.power) >= power
	# Respiração sutil (calma se vencível, tensa/trepidante se ainda for perigoso)
	# dá vida aos inimigos parados sem atrapalhar as poses de combate.
	if enemy_pos != enemy_defeat_target and not (combat_active and enemy_pos == combat_target):
		var idle_phase := (enemy_pos.x*11+enemy_pos.y*17)*.9
		c += Vector2(0, sin(Time.get_ticks_msec()*.0022+idle_phase)*tile_size*.025)
		if is_dangerous: c += Vector2(sin(Time.get_ticks_msec()*.018+idle_phase)*tile_size*.010, 0)
	var palette := [Color("#ef5656"),Color("#6f74df"),Color("#a65bd4"),Color("#ed8b3d"),Color("#35b7a0"),Color("#79bd45"),Color("#d85b9a"),Color("#4b9bd8")]
	var color_index := absi(int(e.power)*31+enemy_pos.x*7+enemy_pos.y*13)%palette.size()
	var enemy_color: Color = palette[color_index]
	var enemy_weapons: Array[String] = ["sword","axe","spear","hammer","staff"]
	var enemy_weapon: String = enemy_weapons[absi(int(e.power)*17+enemy_pos.x*11+enemy_pos.y*5)%enemy_weapons.size()]
	if combat_active and enemy_pos == combat_target and combat_target.x == player.x:
		if player.y < enemy_pos.y:
			draw_texture_rect(ENEMY_BACK_TEXTURE,Rect2(c-Vector2(extent,extent),Vector2.ONE*extent*2.0),false,enemy_color)
			_draw_enemy_held_weapon(enemy_weapon,c,extent,"back")
		else:
			_draw_enemy_front(c,extent,enemy_color,enemy_weapon)
	elif combat_active and enemy_pos == combat_target:
		# O inimigo olha para a casa de origem do herói, nunca para fora da luta.
		var enemy_faces_right := combat_target.x < player.x
		if combat_target.x == player.x: enemy_faces_right = false
		draw_set_transform(c,0.0,Vector2(1.0 if enemy_faces_right else -1.0,1.0))
		_draw_enemy_side_profile(extent,enemy_color,enemy_weapon)
		draw_set_transform(Vector2.ZERO)
	else:
		_draw_enemy_front(c,extent,enemy_color,enemy_weapon)
	if is_boss:
		var crown_rect := Rect2(c+Vector2(-tile_size*.22,-tile_size*.48),Vector2(tile_size*.44,tile_size*.29))
		_draw_atlas_cell(Vector2i(1,1),crown_rect,65.0)
	if show_power:
		# O nível fica sobre a cabeça e muda junto com o poder atual do herói.
		var badge_y := -tile_size*(.60 if is_boss else .47)
		var label := _format_power(int(e.power))
		var font_size := int(tile_size*.17)
		var badge_w := _badge_width(label,font_size,tile_size*.36)
		var badge := Rect2(c+Vector2(-badge_w*.5,badge_y),Vector2(badge_w,tile_size*.20))
		_round_rect(badge,Color("#d74652") if is_dangerous else Color("#43ad72"),tile_size*.055)
		_center_on(label,c.x,badge.position.y+badge.size.y*.72,font_size,Color.WHITE)

func _draw_enemy_front(c: Vector2, extent: float, color: Color, weapon: String) -> void:
	draw_texture_rect(ENEMY_BACK_TEXTURE,Rect2(c-Vector2(extent,extent),Vector2.ONE*extent*2.0),false,color)
	var head := c+Vector2(0,-extent*.31)
	draw_line(head+Vector2(-extent*.25,-extent*.12),head+Vector2(-extent*.08,-extent*.02),Color("#111111"),extent*.07,true)
	draw_line(head+Vector2(extent*.25,-extent*.12),head+Vector2(extent*.08,-extent*.02),Color("#111111"),extent*.07,true)
	draw_circle(head+Vector2(-extent*.13,extent*.02),extent*.055,Color("#111111"))
	draw_circle(head+Vector2(extent*.13,extent*.02),extent*.055,Color("#111111"))
	draw_arc(head+Vector2(0,extent*.25),extent*.16,PI*1.12,PI*1.88,12,Color("#111111"),extent*.055,true)
	_draw_enemy_held_weapon(weapon,c,extent,"front")

func _draw_enemy_side_profile(extent: float, color: Color, weapon: String) -> void:
	# Base lateral sem arma fixa; evita espada duplicada ao variar o equipamento.
	draw_texture_rect(HERO_SIDE_TEXTURE,Rect2(Vector2(-extent,-extent),Vector2.ONE*extent*2.0),false)
	var head := Vector2(extent*.02,-extent*.28)
	draw_circle(head,extent*.39,Color("#111111"))
	draw_circle(head,extent*.34,color)
	draw_colored_polygon(PackedVector2Array([Vector2(-extent*.18,extent*.02),Vector2(extent*.24,extent*.02),Vector2(extent*.28,extent*.50),Vector2(-extent*.14,extent*.50)]),color)
	draw_line(head+Vector2(extent*.10,-extent*.10),head+Vector2(extent*.25,0),Color("#111111"),extent*.065,true)
	draw_circle(head+Vector2(extent*.18,extent*.05),extent*.05,Color("#111111"))
	_draw_enemy_held_weapon(weapon,Vector2.ZERO,extent,"side")

func _draw_enemy_held_weapon(type: String, c: Vector2, extent: float, view: String) -> void:
	# Toda arma nasce exatamente no centro da mão; não depende das margens do atlas.
	# Coordenada da bolinha preta que representa a mão no sprite frontal.
	var shoulder := c+Vector2(-extent*.20,extent*.02)
	var hand := c+Vector2(-extent*.38,extent*.42)
	if view == "side":
		shoulder = c+Vector2(-extent*.02,extent*.04)
		hand = c+Vector2(extent*.05,extent*.26)
	elif view == "back":
		shoulder = c+Vector2(-extent*.20,extent*.02)
		hand = c+Vector2(-extent*.38,extent*.42)
	# O perfil procedural precisa do braço. Frente/costas já o possuem no sprite;
	# desenhá-lo novamente criava um terceiro braço.
	if view == "side":
		draw_line(shoulder,hand,Color("#17171b"),extent*.075,true)
	var shaft_top := hand+Vector2(-extent*.08,-extent*.64)
	var dark := Color("#25252c")
	var wood := Color("#754225")
	var metal := Color("#e7edf3")
	var gold := Color("#e5a900")
	if type == "sword":
		var guard := hand+Vector2(-extent*.02,-extent*.16)
		draw_line(hand,guard,wood,extent*.09,true)
		draw_line(guard+Vector2(-extent*.16,extent*.03),guard+Vector2(extent*.16,-extent*.03),gold,extent*.075,true)
		var blade_tip := guard+Vector2(-extent*.27,-extent*.50)
		draw_line(guard,blade_tip,dark,extent*.16,true)
		draw_line(guard,blade_tip,metal,extent*.10,true)
		draw_circle(hand,extent*.065,gold)
	elif type == "spear":
		draw_line(hand,shaft_top,wood,extent*.085,true)
		# Colar dourado e ponta em folha deixam claro que é uma lança.
		draw_line(shaft_top+Vector2(-extent*.10,extent*.03),shaft_top+Vector2(extent*.10,extent*.01),gold,extent*.07,true)
		var tip := shaft_top+Vector2(-extent*.03,-extent*.30)
		var spear_head := PackedVector2Array([tip,shaft_top+Vector2(-extent*.16,-extent*.02),shaft_top+Vector2(-extent*.01,extent*.07),shaft_top+Vector2(extent*.13,-extent*.04)])
		draw_colored_polygon(spear_head,metal)
		draw_polyline(PackedVector2Array([spear_head[0],spear_head[1],spear_head[2],spear_head[3],spear_head[0]]),dark,extent*.035,true)
	elif type == "axe":
		draw_line(hand,shaft_top,wood,extent*.085,true)
		var axe_head := PackedVector2Array([shaft_top+Vector2(-extent*.22,-extent*.13),shaft_top+Vector2(extent*.08,-extent*.10),shaft_top+Vector2(extent*.11,extent*.13),shaft_top+Vector2(-extent*.17,extent*.08)])
		draw_colored_polygon(axe_head,metal)
		draw_polyline(PackedVector2Array([axe_head[0],axe_head[1],axe_head[2],axe_head[3],axe_head[0]]),dark,extent*.035,true)
	elif type == "hammer":
		draw_line(hand,shaft_top,wood,extent*.09,true)
		var head_rect := Rect2(shaft_top+Vector2(-extent*.23,-extent*.13),Vector2(extent*.43,extent*.22))
		_round_rect(head_rect,Color("#77818d"),extent*.04)
		draw_polyline(PackedVector2Array([head_rect.position,Vector2(head_rect.end.x,head_rect.position.y),head_rect.end,Vector2(head_rect.position.x,head_rect.end.y),head_rect.position]),dark,extent*.035,true)
	else: # cajado
		draw_line(hand,shaft_top,wood,extent*.085,true)
		var crystal := shaft_top+Vector2(-extent*.03,-extent*.15)
		draw_colored_polygon(PackedVector2Array([crystal+Vector2(0,-extent*.13),crystal+Vector2(extent*.11,0),crystal+Vector2(0,extent*.13),crystal+Vector2(-extent*.11,0)]),Color("#55c9ff"))
		draw_circle(crystal,extent*.045,Color.WHITE)
	# A mão é desenhada por cima do cabo para a arma parecer realmente segurada.
	draw_circle(hand,extent*.075,Color("#17171b"))

func _active_attack_style() -> String:
	if not equipment.weapons.is_empty(): return str(equipment.weapons[-1])
	if equipment.shield: return "shield"
	return "fist"

func _draw_item(item: Dictionary) -> void:
	var cell_pos := Vector2i(item.p[0],item.p[1])
	var c := _cell_center(cell_pos); var label: String = config.items[item.type].label
	if item.has("power"): label = "+%s" % _format_power(int(item.power))
	var cells := {"plus1":Vector2i(2,2),"sword":Vector2i(0,1),"helmet":Vector2i(2,1),"crown":Vector2i(1,1),"heart":Vector2i(0,2),"double":Vector2i(1,2)}
	var equipment_cells := {"axe":Vector2i(0,0),"spear":Vector2i(1,0),"hammer":Vector2i(2,0),"shield":Vector2i(0,1),"armor":Vector2i(1,1),"cape":Vector2i(2,1),"boots":Vector2i(0,2),"amulet":Vector2i(1,2),"staff":Vector2i(2,2)}
	var extent := tile_size*.34
	var crop := 65.0 if item.type in ["crown", "helmet", "plus1"] else 28.0
	# Flutuação suave + brilho passageiro: o ícone "chama atenção" sem se mexer
	# tanto a ponto de ficar difícil de mirar no toque (a área de toque continua
	# fixa na casa, só o desenho balança).
	var phase := (cell_pos.x*13+cell_pos.y*7)*.7
	var icon_c := c+Vector2(0, sin(Time.get_ticks_msec()*.0028+phase)*tile_size*.045)
	if equipment_cells.has(item.type): _draw_equipment_cell(equipment_cells[item.type],Rect2(icon_c-Vector2(extent,extent),Vector2.ONE*extent*2.0))
	else: _draw_atlas_cell(cells[item.type], Rect2(icon_c-Vector2(extent,extent),Vector2.ONE*extent*2.0), crop)
	var glint := fmod(Time.get_ticks_msec()*.001+phase, 2.4)
	if glint < .5:
		var glint_alpha := 1.0-glint/.5
		draw_circle(icon_c+Vector2(-extent*.3,-extent*.3), extent*.10*glint_alpha, Color(1,1,1,.55*glint_alpha))
	var item_font_size := int(clampf(tile_size*.16,13,25))
	var badge_w := _badge_width(label,item_font_size,tile_size*.46)
	var badge := Rect2(c+Vector2(-badge_w*.5,tile_size*.20),Vector2(badge_w,tile_size*.22))
	_round_rect(badge,Color("#5a4975"),tile_size*.05)
	_center_on(label,c.x,c.y+tile_size*.365,item_font_size,Color.WHITE)

func _draw_lifted_item(hero_center: Vector2) -> void:
	if pickup_item_index < 0 or pickup_item_index >= level.get("items",[]).size(): return
	var item: Dictionary = level.items[pickup_item_index]
	var elapsed := PICKUP_MOVE_DURATION+PICKUP_LIFT_DURATION-pickup_time
	var lift_progress := clampf((elapsed-PICKUP_MOVE_DURATION)/PICKUP_LIFT_DURATION,0.0,1.0)
	# O item sai da lateral do corpo e vai para cima da mão; nunca cruza o rosto.
	var side := 1.0 if move_direction.x >= 0 else -1.0
	if move_direction.x == 0: side = 1.0
	var start := hero_center+Vector2(side*tile_size*.30,tile_size*.13)
	var hand_point := hero_center+Vector2(side*tile_size*.31,-tile_size*.05)
	var raised := hero_center+Vector2(side*tile_size*.20,-tile_size*.48)
	var c: Vector2
	if lift_progress < .45:
		c = start.lerp(hand_point,smoothstep(0.0,1.0,lift_progress/.45))
	else:
		c = hand_point.lerp(raised,smoothstep(0.0,1.0,(lift_progress-.45)/.55))
	var shoulder := hero_center+Vector2(side*tile_size*.13,-tile_size*.01)
	var hand_reach := shoulder.lerp(c,clampf(lift_progress*1.5,0.0,1.0))
	draw_line(shoulder,hand_reach,Color("#17171b"),tile_size*.025,true)
	draw_circle(hand_reach,tile_size*.025,Color("#17171b"))
	var extent := tile_size*(.115+.015*sin(lift_progress*PI))
	var cells := {"plus1":Vector2i(2,2),"sword":Vector2i(0,1),"helmet":Vector2i(2,1),"crown":Vector2i(1,1),"heart":Vector2i(0,2),"double":Vector2i(1,2)}
	var equipment_cells := {"axe":Vector2i(0,0),"spear":Vector2i(1,0),"hammer":Vector2i(2,0),"shield":Vector2i(0,1),"armor":Vector2i(1,1),"cape":Vector2i(2,1),"boots":Vector2i(0,2),"amulet":Vector2i(1,2),"staff":Vector2i(2,2)}
	if equipment_cells.has(item.type):
		_draw_equipment_cell(equipment_cells[item.type],Rect2(c-Vector2(extent,extent),Vector2.ONE*extent*2.0))
	elif cells.has(item.type):
		var crop := 65.0 if item.type in ["crown","helmet","plus1"] else 28.0
		_draw_atlas_cell(cells[item.type],Rect2(c-Vector2(extent,extent),Vector2.ONE*extent*2.0),crop)

func _draw_atlas_cell(cell: Vector2i, destination: Rect2, top_crop := 0.0) -> void:
	var source := Rect2(Vector2(cell) * ATLAS_CELL + Vector2(0, top_crop), Vector2(ATLAS_CELL, ATLAS_CELL-top_crop))
	draw_texture_rect_region(ATLAS_TEXTURE, destination, source)

func _draw_equipment_cell(cell: Vector2i, destination: Rect2) -> void:
	var source := Rect2(Vector2(cell)*ATLAS_CELL,Vector2.ONE*ATLAS_CELL)
	draw_texture_rect_region(EQUIPMENT_TEXTURE,destination,source)

func _cell_center(p: Vector2i) -> Vector2: return board_rect.position + (Vector2(p)+Vector2(.5,.5))*tile_size
# Poder pode chegar a dezenas de milhares (a geração das fases é multiplicativa).
# Sem abreviar, o número furava a largura fixa do balão. "24342" -> "24k".
func _format_power(n: int) -> String:
	var value := absi(n)
	if value >= 10000: return "%dk" % int(value/1000.0)
	if value >= 1000: return "%.1fk" % (value/1000.0)
	return str(n)
# Largura do balão acompanha o texto (com abreviação isso raramente cresce,
# mas nunca mais corta/estoura o número por fora).
func _badge_width(label: String, font_size: int, min_width: float) -> float:
	var text_w := ThemeDB.fallback_font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	return maxf(min_width, text_w + font_size*.7)
func _round_rect(r: Rect2, color: Color, radius: float) -> void: draw_style_box(_box(color,radius),r)
func _box(color: Color, radius: float) -> StyleBoxFlat:
	var b:=StyleBoxFlat.new(); b.bg_color=color; b.set_corner_radius_all(int(radius)); return b
func _text(t:String,p:Vector2,font_size:int,color:Color)->void: draw_string(ThemeDB.fallback_font,p,t,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)
func _center_text(t:String,y:float,font_size:int,color:Color)->void: _center_at(t,y,font_size,color)
func _center_at(t:String,y:float,font_size:int,color:Color)->void:
	var w:=ThemeDB.fallback_font.get_string_size(t,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x; _text(t,Vector2((size.x-w)/2,y),font_size,color)
func _center_on(t:String,x:float,y:float,font_size:int,color:Color)->void:
	var w:=ThemeDB.fallback_font.get_string_size(t,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x; _text(t,Vector2(x-w/2,y),font_size,color)

func _load_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH)); if data is Dictionary: unlocked = clampi(int(data.get("unlocked",1)),1,MAX_STAGE)
func _save() -> void:
	var f := FileAccess.open(SAVE_PATH,FileAccess.WRITE)
	if f == null:
		push_error("Não foi possível salvar o progresso (%s)" % error_string(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify({"unlocked":unlocked}))
