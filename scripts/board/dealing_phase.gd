extends Node

signal finished

const DEAL_DELAY = 0.35
const DEAL_DURATION = 0.7
const FLIP_DELAY_AFTER_DEAL = 0.6
const FLIP_WAVE_DELAY = 0.12
const CARD_BACK_FALLBACK := preload("res://assets/art/cards/carte-sauvage-dos.png")
const CARD_VISUAL_SCALE := 0.5
const PILE_DROP_HEIGHT := 260.0
const PILE_DROP_DURATION := 0.6
const PILE_DROP_DELAY := 0.18
const CARD_START_JITTER := 0.35
const CARD_MIN_DROP_DURATION := 0.35
const CARDS_PER_PILE := 10
const CARD_STACK_OFFSET := Vector2(0, -2)
const CARD_PILE_STAGGER := 0.05
const CARD_LANDING_JITTER_PX := 10.0
const CARD_LANDING_JITTER_DEG := 10.0
const CARD_SETTLE_DELAY := 0.5
const CARD_SETTLE_DURATION := 0.3
const FLIP_WAVE_TRAIL := 0.3

var _card_back_cache: Dictionary = {}
var _board: Board
var _dealt_count: int = 0


func start(board: Board) -> void:
	_board = board
	_board.deck_area.deck_clicked.connect(_on_deck_clicked)
	_board.deck_area.hover_entered.connect(_on_deck_hover_entered)
	_board.deck_area.hover_exited.connect(_on_deck_hover_exited)
	_board.narration_box.say(tr("Cliquez sur la pile pour distribuer les mers."))


func _on_deck_hover_entered() -> void:
	if not _board._has_started and _board._sea_tiles.size() > 0:
		_board._sea_tiles[-1].modulate = UiTheme.HOVER_TINT


func _on_deck_hover_exited() -> void:
	if _board._sea_tiles.size() > 0:
		_board._sea_tiles[-1].modulate = Color.WHITE


func _on_deck_clicked() -> void:
	if _board._has_started:
		return
	_board._has_started = true
	_board.narration_box.hide_box()
	_board.deck_area.get_node("HoverPrompt").hide_prompt()
	_board.deck_area.input_pickable = false
	_board.deck_area.visible = false
	_deal_seas()


func _deal_seas() -> void:
	var deal_delay: float = Settings.anim_duration(DEAL_DELAY)
	var deal_duration: float = Settings.anim_duration(DEAL_DURATION)
	var deal_count = 0
	for i in range(_board._sea_tiles.size() - 1, -1, -1):
		var tile = _board._sea_tiles[i]
		tile.z_index = 0
		var target_pos = tile.get_meta("target_global_position")
		var target_rot = tile.get_meta("target_rotation")

		var tween = create_tween()
		tween.tween_interval(deal_count * deal_delay)
		tween.tween_property(tile, "global_position", target_pos, deal_duration)\
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(tile, "rotation_degrees", target_rot, deal_duration)\
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_callback(_on_one_card_dealt)
		deal_count += 1


func _on_one_card_dealt() -> void:
	_dealt_count += 1
	if _dealt_count == _board._total_seas:
		await get_tree().create_timer(Settings.anim_duration(FLIP_DELAY_AFTER_DEAL)).timeout
		_flip_all_as_wave()


func _flip_all_as_wave() -> void:
	var flip_wave_delay: float = Settings.anim_duration(FLIP_WAVE_DELAY)
	for i in range(_board._slot_order.size()):
		var tile = _board._slot_order[i]
		var t = get_tree().create_timer(i * flip_wave_delay)
		t.timeout.connect(tile.flip_to_front)

	var total_delay := (_board._slot_order.size() - 1) * flip_wave_delay + Settings.anim_duration(FLIP_WAVE_TRAIL)
	await get_tree().create_timer(total_delay).timeout
	await _drop_card_piles()
	finished.emit()


func _get_card_back_texture(sea_key: String) -> Texture2D:
	if _card_back_cache.has(sea_key):
		return _card_back_cache[sea_key]
	var path := "res://assets/art/cards/carte-%s-dos.png" % sea_key
	var texture: Texture2D = load(path) if ResourceLoader.exists(path) else CARD_BACK_FALLBACK
	_card_back_cache[sea_key] = texture
	return texture


func _drop_card_piles() -> void:
	var piles := _board.card_piles_container.get_children()
	for pile in piles:
		pile.visible = true

	var token_count: int = _board.token_count_for_player_count(GameFlow.players.size())
	for token_pile in _board.token_piles_container.get_children():
		token_pile.remaining_count = token_count
		token_pile.visible = true

	var pile_drop_duration: float = Settings.anim_duration(PILE_DROP_DURATION)
	var pile_drop_delay : float = Settings.anim_duration(PILE_DROP_DELAY)
	var card_pile_stagger : float = Settings.anim_duration(CARD_PILE_STAGGER)
	var card_settle_delay : float = Settings.anim_duration(CARD_SETTLE_DELAY)
	var card_settle_duration : float = Settings.anim_duration(CARD_SETTLE_DURATION)

	var cards_info: Array = []
	var max_landing_time := 0.0

	for round_i in range(CARDS_PER_PILE):
		for pile_i in range(piles.size()):
			var pile: Node2D = piles[pile_i]
			var stack_pos: Vector2 = CARD_STACK_OFFSET * round_i
			var card: Sprite2D = pile.add_visual_card(_get_card_back_texture(pile.sea_key), stack_pos)
			card.scale = Vector2.ONE * CARD_VISUAL_SCALE
			var target_global_pos: Vector2 = card.global_position
			card.global_position = target_global_pos - Vector2(0, PILE_DROP_HEIGHT)
			card.modulate.a = 0.0

			var jitter := randf_range(0.0, Settings.anim_duration(CARD_START_JITTER))
			var fall_duration: float = max(pile_drop_duration - jitter, Settings.anim_duration(CARD_MIN_DROP_DURATION))
			var start_delay := round_i * pile_drop_delay + pile_i * card_pile_stagger + jitter

			var landing_offset := Vector2(
				randf_range(-CARD_LANDING_JITTER_PX, CARD_LANDING_JITTER_PX),
				randf_range(-CARD_LANDING_JITTER_PX, CARD_LANDING_JITTER_PX)
			)
			var landing_rotation_deg := randf_range(-CARD_LANDING_JITTER_DEG, CARD_LANDING_JITTER_DEG)

			var tween := create_tween()
			tween.tween_interval(start_delay)
			tween.tween_property(card, "global_position", target_global_pos + landing_offset, fall_duration)\
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tween.parallel().tween_property(card, "modulate:a", 1.0, min(fall_duration * 0.7, fall_duration))
			tween.parallel().tween_property(card, "rotation_degrees", landing_rotation_deg, fall_duration)\
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

			var landing_time := start_delay + fall_duration
			max_landing_time = max(max_landing_time, landing_time)
			cards_info.append({"card": card, "target_pos": target_global_pos, "landing_time": landing_time})

	var settle_start_time := max_landing_time + card_settle_delay
	for info in cards_info:
		var settle_tween := create_tween()
		settle_tween.tween_interval(settle_start_time)
		settle_tween.tween_property(info["card"], "global_position", info["target_pos"], card_settle_duration)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		settle_tween.parallel().tween_property(info["card"], "rotation_degrees", 0.0, card_settle_duration)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	await get_tree().create_timer(settle_start_time + card_settle_duration).timeout
