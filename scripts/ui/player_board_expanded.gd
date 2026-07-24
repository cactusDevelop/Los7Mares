extends Control

## --- Position des éléments sur l'image du plateau joueur ---
## Toutes les coordonnées ci-dessous sont en PIXELS DE L'IMAGE D'ORIGINE
## (assets/art/board/plateau-joueur-jaune.png, 2716x1813), pas en pixels
## écran : le script convertit automatiquement selon la taille affichée.
##
## --- Persistance & drag & drop (inventaire) ---
## La position réelle de chaque objet (ressource, jeton, planche) est
## mémorisée dans player["inventory_layout"], qui est sauvegardée avec la
## partie (GameFlow.autosave -> SaveManager, car "player" est une référence
## directe vers l'entrée dans GameFlow.players). Au premier affichage, les
## positions sont générées comme avant (aléatoire dans leur zone pour les
## jetons/planches, slots fixes pour les ressources), puis elles restent
## figées et modifiables par glisser-déposer :
## - Ressources classiques : 9 slots fixes, on peut prendre une ressource et
##   la déposer sur une autre pour les échanger (swap).
## - Jetons Fortune/Trésor et planches : position libre mais bornée à
##   l'intérieur de leur propre zone ("carré").

const RESOURCE_SLOT_PIXELS: Array[Vector2] = [
	Vector2(2100, 1320), Vector2(2250, 1320), Vector2(2400, 1320),
	Vector2(2100, 1470), Vector2(2250, 1470), Vector2(2400, 1470),
	Vector2(2100, 1620), Vector2(2250, 1620), Vector2(2400, 1620),
]
## Zones (coin haut-gauche -> coin bas-droit) dans lesquelles les jetons
## Trésor / Fortune apparaissent (position initiale aléatoire, puis bornées
## lors du glisser-déposer).
const TREASURE_RECT_MIN := Vector2(100, 925)
const TREASURE_RECT_MAX := Vector2(790, 1310)
const FORTUNE_RECT_MIN := Vector2(100, 1350)
const FORTUNE_RECT_MAX := Vector2(800, 1720)
## Zone ("carré") dans laquelle les planches de coque peuvent être
## déplacées librement par glisser-déposer.
const PLANK_RECT_MIN := Vector2(880, 1250)
const PLANK_RECT_MAX := Vector2(1930, 1700)

## --- Pistes de cartes (Exploration/Combat/Commerce, règle 3) ---
## Bande à droite du plateau (au-delà des cubes de ressources, qui
## s'arrêtent vers x=2460), divisée en 3 tiers de même hauteur : Exploration
## (tiers supérieur), Combat (tiers central), Commerce (tiers inférieur).
## À ajuster si la largeur réelle réservée sur l'illustration diffère.
const CARD_TRACK_RECT_MIN := Vector2(2450, 0)
const CARD_TRACK_RECT_MAX := Vector2(2716, 1813)
## Distance verticale (pixels image du plateau) entre le centre de la piste
## centrale (combat) et le centre de chacune des 2 autres pistes
## (exploration au-dessus, commerce en-dessous). La piste centrale est
## toujours exactement au milieu vertical de CARD_TRACK_RECT ; les 2 autres
## sont réparties symétriquement à cette distance, réglable ici.
const CARD_TRACK_CENTER_SPACING := 565.5
## Largeur totale (pixels image du plateau) que le bord droit de la DERNIÈRE
## carte d'une pile peut dépasser au-delà de CARD_TRACK_RECT_MAX.x (bord
## droit du plateau). Cette largeur totale reste la même quel que soit le
## nombre de cartes dans la pile : le dépassement de chaque carte
## individuelle est reparti/réduit en conséquence (carte i sur N dépasse de
## (i+1)/N * CARD_TRACK_OVERHANG_TOTAL), la 1ère carte étant donc la moins
## visible et la dernière atteignant toujours ce dépassement maximal.
const CARD_TRACK_OVERHANG_TOTAL := 280.0
## Largeur cible d'une carte de piste, en pixels image du plateau. Ne dépend
## plus de la résolution native des assets (qui varie selon les fichiers, ce
## qui rendait la taille imprévisible) : la hauteur est déduite du ratio
## largeur/hauteur natif de chaque image pour ne pas la déformer. À monter
## si les cartes paraissent trop petites, descendre si trop grandes. Les
## cartes dépassent volontairement de la bande (voir CARD_TRACK_OVERHANG_TOTAL
## ci-dessus) : ce n'est donc plus borné à la largeur de la bande.
const CARD_TRACK_WIDTH := 680.0
## Au survol d'une pile de cartes (piste), les cartes sont assombries et un
## compteur blanc affiche leur nombre, centré sur la pile.
const CARD_TRACK_HOVER_DARKEN := Color(0.12, 0.12, 0.12)
const CARD_TRACK_COUNT_FONT_SIZE := 30
const CARD_TRACK_COUNT_OUTLINE_SIZE := 6
## Durée de l'animation (assombrissement des cartes + apparition du chiffre)
## au survol d'une piste, en secondes. Très rapide par défaut.
const CARD_TRACK_HOVER_ANIM_DURATION := 0.1

const RESOURCE_CUBE_EDGE := 120.0
const SPECIAL_ICON_SIZE := Vector2(110, 110)
## Distance minimale visée (en pixels image) entre deux jetons du même type,
## pour limiter les superpositions sans les interdire totalement.
const SPECIAL_TOKEN_MIN_DISTANCE := 95.0
const SPECIAL_TOKEN_MAX_ATTEMPTS := 40

## --- Cohérence de la fausse perspective 3D ---
## La direction (UiTheme.DEPTH_DIRECTION) est définie une seule fois dans
## UiTheme pour rester identique partout dans le jeu (ressources, planches,
## jetons, bateaux...). Convention : la "matière"/l'épaisseur des objets
## s'étend vers le BAS-GAUCHE À L'ÉCRAN (comme une ombre portée), donc leur
## face du dessus/avant visible est repoussée vers le HAUT-DROITE. Les
## cubes de ressource DOIVENT utiliser la direction opposée à celle-ci.
## Épaisseur totale des jetons Fortune/Trésor, en pixels écran (~3px demandés).
## Géré par empilement de TextureRect (_add_token_with_thickness ci-dessous),
## comme les pièces capitaine/second (scripts/common/pion_thickness.gd) et
## les bateaux (hideout_spot.gd). Ici les nodes restent séparés (pas enfants
## les uns des autres) car ils doivent être déplacés ensemble pendant un
## glisser-déposer via le tableau "nodes" de _draggable_items.
const TOKEN_THICKNESS_PX := 3.0
const TOKEN_THICKNESS_LAYERS := 3
const TOKEN_EDGE_DARKEN := 0.45
## Hauteur du cube = fraction de son côté (edge), extrudée en sens opposé
## à DEPTH_DIRECTION pour rester cohérente avec les jetons.
const CUBE_EXTRUDE_RATIO := 0.22

const RESOURCE_CUBE_COLORS := {
	"wood": Color8(122, 74, 34),    # brun
	"steel": Color8(58, 62, 68),    # gris foncé
	"food": Color8(235, 140, 30),   # orange
	"rum": Color8(50, 200, 190),    # turquoise
	"wool": Color(1, 1, 1),         # blanc
}

const FORTUNE_TEXTURE := preload("res://assets/art/tokens/fortune.png")
const TREASURE_TEXTURE := preload("res://assets/art/tokens/tresor.png")

## Planches de coque (= points de vie), verticales. Position initiale
## aléatoire dans PLANK_RECT (comme les jetons Fortune/Trésor) ; ensuite la
## position réelle vient de player["inventory_layout"]["plank_pos"].
const PLANK_SIZE := Vector2(80, 240)
const PLANK_ROTATION_JITTER_DEG := 4.0  # légère inclinaison aléatoire pour un rendu moins rigide

@onready var blocker: ColorRect = $Blocker
@onready var padding: MarginContainer = $Padding
@onready var title_label: Label = $Padding/Content/TitleLabel
@onready var board_texture: TextureRect = $Padding/Content/BoardArea/BoardStack/BoardTexture
@onready var resource_slots: Control = $Padding/Content/BoardArea/BoardStack/ResourceSlots
@onready var card_track_slots: Control = $Padding/Content/BoardArea/BoardStack/CardTrackSlots
@onready var close_button: Button = $Padding/Content/CloseButton

## Joueur actuellement affiché (référence directe vers l'entrée dans
## GameFlow.players, donc toute modification est automatiquement persistée
## au prochain GameFlow.autosave()).
var _current_player: Dictionary = {}

## Liste des objets actuellement affichés et déplaçables : chaque entrée est
## {"kind": "resource"|"treasure"|"fortune"|"plank", "index": int,
##  "rect": Rect2 (en coordonnées locales de resource_slots), "nodes": [Node]}
var _draggable_items: Array[Dictionary] = []
var _dragging_item: Dictionary = {}
var _drag_active: bool = false
var _drag_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.color = Color(0, 0, 0, 0.7)
	board_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	board_texture.stretch_mode = TextureRect.STRETCH_SCALE
	# Les cartes des pistes sont dessinées derrière le plateau : seule la
	# partie qui dépasse du bord droit du plateau (hors de la zone couverte
	# par BoardTexture) reste visible.
	board_texture.z_index = 10
	padding.add_theme_constant_override("margin_left", 0)
	padding.add_theme_constant_override("margin_right", 0)
	padding.add_theme_constant_override("margin_top", 60)
	padding.add_theme_constant_override("margin_bottom", 0)
	if close_button.text == "":
		close_button.text = tr("Retour")
	close_button.custom_minimum_size = Vector2(0, 64)
	close_button.pressed.connect(func(): visible = false)
	blocker.gui_input.connect(_on_blocker_gui_input)

	resource_slots.mouse_filter = Control.MOUSE_FILTER_STOP
	resource_slots.gui_input.connect(_on_resource_slots_gui_input)
	set_process_input(true)


func show_player(player: Dictionary) -> void:
	title_label.text = player["name"]
	title_label.add_theme_color_override("font_color", GameFlow.COLOR_VALUES[player["color"]])
	var texture_path: String = GameFlow.PLAYER_BOARD_TEXTURES.get(
		player["color"], GameFlow.PLAYER_BOARD_TEXTURES["jaune"]
	)
	board_texture.texture = load(texture_path)

	var viewport_size := get_viewport_rect().size
	blocker.size = viewport_size
	padding.position = Vector2.ZERO
	padding.size = viewport_size
	visible = true

	# Le BoardTexture doit avoir sa taille finale à jour avant de convertir
	# les coordonnées pixel -> écran : on attend une frame de layout.
	await get_tree().process_frame
	_refresh_resource_display(player)


## Place un cube coloré par unité de ressource simple (bois/acier/nourriture/
## rhum/laine) sur les cases d'inventaire, et des jetons Fortune/Trésor et des
## planches de coque, tous à leur position mémorisée (player["inventory_layout"]).
func _refresh_resource_display(player: Dictionary) -> void:
	for child in resource_slots.get_children():
		child.queue_free()
	_draggable_items.clear()
	_current_player = player

	_ensure_inventory_layout(player)
	var layout: Dictionary = player["inventory_layout"]

	var edge_local: float = _texture_length_to_local(RESOURCE_CUBE_EDGE)
	var slots: Array = layout["resource_slots"]
	for i in range(slots.size()):
		var res_type: String = slots[i]
		if res_type == "":
			continue
		var cube := _build_cube_icon(RESOURCE_CUBE_COLORS.get(res_type, Color.MAGENTA), edge_local)
		resource_slots.add_child(cube)
		var center: Vector2 = _texture_to_local(RESOURCE_SLOT_PIXELS[i])
		cube.position = center
		var half := edge_local / 2.0
		_draggable_items.append({
			"kind": "resource", "index": i,
			"rect": Rect2(center - Vector2(half, half), Vector2(edge_local, edge_local)),
			"nodes": [cube],
		})

	_place_special_tokens("treasure", TREASURE_TEXTURE, layout, "treasure_pos")
	_place_special_tokens("fortune", FORTUNE_TEXTURE, layout, "fortune_pos")
	_place_hull_planks_from_layout(layout)
	_refresh_card_tracks(player)


## Affiche les 3 piles de cartes (Exploration/Combat/Commerce, règle 3) dans
## la bande de droite, une carte du dessus visible par pile avec un décalage
## cosmétique montrant les suivantes (règle 3 : le décalage n'a aucun effet
## de jeu). Utilise la vraie image de carte quand un asset existe pour
## sea_key+card_type (CardArt), sinon une pastille de couleur + un chiffre.
func _refresh_card_tracks(player: Dictionary) -> void:
	for child in card_track_slots.get_children():
		child.queue_free()

	# Milieu vertical de la zone : la piste centrale (index 1 = combat) y est
	# alignée exactement ; les 2 autres pistes sont décalées symétriquement
	# de CARD_TRACK_CENTER_SPACING de part et d'autre.
	var area_center_y: float = (CARD_TRACK_RECT_MIN.y + CARD_TRACK_RECT_MAX.y) / 2.0
	@warning_ignore("integer_division")
	var mid_band_index: int = GameFlow.CARD_TRACK_KEYS.size() / 2

	for band_index in range(GameFlow.CARD_TRACK_KEYS.size()):
		var track: String = GameFlow.CARD_TRACK_KEYS[band_index]
		var track_center_y: float = area_center_y + (band_index - mid_band_index) * CARD_TRACK_CENTER_SPACING
		var cards: Array = player.get("card_tracks", {}).get(track, [])
		var count: int = cards.size()

		var pile_cards: Array[Control] = []
		var pile_rect_min := Vector2.INF
		var pile_rect_max := -Vector2.INF

		for i in range(count):
			var entry: Dictionary = cards[i]
			var card_type: int = entry.get("card_type", GameCard.CardType.RENCONTRE)
			var texture: Texture2D = null
			var pool := CardArt.get_background_pool(entry.get("sea_key", ""), card_type)
			if not pool.is_empty():
				texture = pool[0]

			# Taille "pixels plateau" : largeur fixe réglable (CARD_TRACK_WIDTH),
			# hauteur déduite du ratio natif de l'image pour ne pas la
			# déformer. On ne borne plus à la largeur de la bande : les
			# cartes dépassent volontairement du plateau (voir
			# CARD_TRACK_OVERHANG_TOTAL).
			var native_size: Vector2 = texture.get_size() if texture else Vector2(807, 513)
			var board_size: Vector2 = Vector2(
				CARD_TRACK_WIDTH, CARD_TRACK_WIDTH * native_size.y / native_size.x
			)

			var card_node: Control
			if texture:
				var rect := TextureRect.new()
				rect.texture = texture
				rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				rect.stretch_mode = TextureRect.STRETCH_SCALE
				card_node = rect
			else:
				var placeholder := ColorRect.new()
				placeholder.color = GameFlow.CARD_TRACK_COLORS.get(track, Color.MAGENTA)
				card_node = placeholder
			card_node.mouse_filter = Control.MOUSE_FILTER_IGNORE

			card_track_slots.add_child(card_node)
			var local_size: Vector2 = _texture_size_to_local(board_size)
			card_node.size = local_size

			# Dépassement horizontal : la carte i (sur "count") dépasse du
			# bord droit du plateau de (i+1)/count * CARD_TRACK_OVERHANG_TOTAL.
			# Ainsi la dernière carte de la pile dépasse toujours du même
			# total, quel que soit le nombre de cartes empilées ; les cartes
			# précédentes dépassent proportionnellement moins.
			var overhang: float = (float(i + 1) / float(count)) * CARD_TRACK_OVERHANG_TOTAL
			var top_left_px := Vector2(
				CARD_TRACK_RECT_MAX.x - board_size.x + overhang,
				track_center_y - board_size.y / 2.0
			)
			card_node.position = _texture_to_local(top_left_px)
			# Toutes les cartes sont dessinées sous le plateau (voir
			# board_texture.z_index = 10) : seule la partie qui dépasse du
			# bord droit reste visible pour chaque carte. Pour que cette
			# partie visible de CHAQUE carte reste distincte (effet
			# d'éventail), la carte la MOINS dépassante doit être devant
			# (z-index le plus haut) et la PLUS dépassante derrière (z-index
			# le plus bas) : sinon la dernière carte (qui dépasse le plus)
			# recouvre entièrement le petit bout visible de toutes les
			# précédentes.
			card_node.z_index = count - 1 - i

			pile_cards.append(card_node)
			pile_rect_min = pile_rect_min.min(card_node.position)
			pile_rect_max = pile_rect_max.max(card_node.position + local_size)

		if count > 0:
			_add_track_hover_zone(track, count, pile_cards, pile_rect_min, pile_rect_max)


## Ajoute une zone invisible couvrant toute la pile d'une piste : au survol,
## assombrit toutes les cartes de la pile et affiche un compteur blanc
## (nombre de cartes) centré dessus.
func _add_track_hover_zone(
	track: String, count: int, pile_cards: Array[Control], rect_min: Vector2, rect_max: Vector2
) -> void:
	var hover_zone := Control.new()
	hover_zone.mouse_filter = Control.MOUSE_FILTER_STOP
	hover_zone.position = rect_min
	hover_zone.size = rect_max - rect_min
	hover_zone.z_index = count + 10
	card_track_slots.add_child(hover_zone)

	var count_label := Label.new()
	count_label.text = str(count)
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count_label.position = rect_min
	count_label.size = rect_max - rect_min
	count_label.add_theme_color_override("font_color", Color.WHITE)
	count_label.add_theme_font_size_override("font_size", CARD_TRACK_COUNT_FONT_SIZE)
	count_label.add_theme_color_override("font_outline_color", Color.BLACK)
	count_label.add_theme_constant_override("outline_size", CARD_TRACK_COUNT_OUTLINE_SIZE)
	count_label.z_index = count + 11
	count_label.visible = false
	count_label.modulate.a = 0.0
	card_track_slots.add_child(count_label)

	# Tween partagé par cette pile (survol multiple rapide = on interrompt
	# l'animation en cours plutôt que de les empiler).
	var hover_tween: Tween = null

	hover_zone.mouse_entered.connect(func():
		if hover_tween:
			hover_tween.kill()
		count_label.visible = true
		hover_tween = create_tween().set_parallel(true)
		for c in pile_cards:
			hover_tween.tween_property(c, "modulate", CARD_TRACK_HOVER_DARKEN, CARD_TRACK_HOVER_ANIM_DURATION)
		hover_tween.tween_property(count_label, "modulate:a", 1.0, CARD_TRACK_HOVER_ANIM_DURATION)
	)
	hover_zone.mouse_exited.connect(func():
		if hover_tween:
			hover_tween.kill()
		hover_tween = create_tween().set_parallel(true)
		for c in pile_cards:
			hover_tween.tween_property(c, "modulate", Color.WHITE, CARD_TRACK_HOVER_ANIM_DURATION)
		hover_tween.tween_property(count_label, "modulate:a", 0.0, CARD_TRACK_HOVER_ANIM_DURATION)
		hover_tween.chain().tween_callback(func(): count_label.visible = false)
	)


## Crée / met à jour player["inventory_layout"] pour qu'il corresponde
## exactement aux quantités actuelles du joueur (resources, special_resources,
## hull_planks), en générant une position initiale (aléatoire pour les jetons
## et les planches au-delà des 7 slots historiques, slot libre pour les
## ressources) uniquement pour les nouveaux objets, et en retirant les
## positions des objets qui ont été dépensés/perdus. Les positions déjà
## connues (placées à la main par le joueur) ne sont jamais modifiées ici.
func _ensure_inventory_layout(player: Dictionary) -> void:
	if not player.has("inventory_layout"):
		player["inventory_layout"] = {}
	var layout: Dictionary = player["inventory_layout"]

	# --- Ressources classiques : 9 slots fixes, contenu échangeable ---
	var slot_count := RESOURCE_SLOT_PIXELS.size()
	var slots: Array = layout.get("resource_slots", [])
	while slots.size() < slot_count:
		slots.append("")
	slots = slots.slice(0, slot_count)
	for res_type in GameFlow.RESOURCE_TYPES:
		var wanted: int = player["resources"].get(res_type, 0)
		var have: int = slots.count(res_type)
		if have < wanted:
			for i in range(slot_count):
				if have >= wanted:
					break
				if slots[i] == "":
					slots[i] = res_type
					have += 1
		elif have > wanted:
			for i in range(slot_count - 1, -1, -1):
				if have <= wanted:
					break
				if slots[i] == res_type:
					slots[i] = ""
					have -= 1
	layout["resource_slots"] = slots

	# --- Jetons Fortune / Trésor : position libre dans leur carré ---
	_ensure_free_positions(layout, "treasure_pos",
		player["special_resources"].get("treasure", 0), TREASURE_RECT_MIN, TREASURE_RECT_MAX, SPECIAL_ICON_SIZE)
	_ensure_free_positions(layout, "fortune_pos",
		player["special_resources"].get("fortune", 0), FORTUNE_RECT_MIN, FORTUNE_RECT_MAX, SPECIAL_ICON_SIZE)

	# --- Planches de coque : position libre dans leur carré ---
	_ensure_free_positions(layout, "plank_pos",
		player.get("hull_planks", 0), PLANK_RECT_MIN, PLANK_RECT_MAX, PLANK_SIZE)
	_ensure_plank_style(layout)

	player["inventory_layout"] = layout


## Ajuste le tableau layout[key] (liste de [x, y], le centre de chaque objet)
## pour qu'il contienne exactement `count` positions, en ajoutant des
## positions aléatoires espacées si besoin, ou en retirant les dernières si
## le joueur a perdu des objets de ce type.
## `icon_size` (taille de l'objet, en pixels image) sert à rétrécir la zone
## de tirage de la moitié de la taille de l'icône sur chaque bord : sans ça,
## un objet tiré tout contre rect_max/rect_min dépasserait de son propre
## rectangle, alors que le glisser-déposer, lui, garde toute l'icône dedans
## (incohérence entre apparition et zone de déplacement autorisée).
func _ensure_free_positions(layout: Dictionary, key: String, count: int, rect_min: Vector2, rect_max: Vector2, icon_size: Vector2) -> void:
	var half := icon_size / 2.0
	var safe_min := Vector2(min(rect_min.x + half.x, (rect_min.x + rect_max.x) / 2.0),
		min(rect_min.y + half.y, (rect_min.y + rect_max.y) / 2.0))
	var safe_max := Vector2(max(rect_max.x - half.x, safe_min.x),
		max(rect_max.y - half.y, safe_min.y))

	var positions: Array = layout.get(key, [])
	if positions.size() < count:
		var existing: Array[Vector2] = []
		for p in positions:
			existing.append(Vector2(p[0], p[1]))
		for i in range(positions.size(), count):
			var pixel := _pick_spaced_position(safe_min, safe_max, existing)
			existing.append(pixel)
			positions.append([pixel.x, pixel.y])
	elif positions.size() > count:
		positions = positions.slice(0, count)
	layout[key] = positions


## Chaque entrée de layout["plank_pos"] est [x, y] au moment de sa création
## (par _ensure_free_positions) ; on lui ajoute ici une variation de couleur
## (index 2) et une rotation (index 3), tirées aléatoirement une seule fois
## puis conservées pour toujours (sinon la planche change d'aspect à chaque
## réaffichage du panneau, ce qui est perturbant).
func _ensure_plank_style(layout: Dictionary) -> void:
	var planks: Array = layout.get("plank_pos", [])
	for i in range(planks.size()):
		var p: Array = planks[i]
		if p.size() < 3:
			p.append(randf_range(-0.1, 0.1))
		if p.size() < 4:
			p.append(randf_range(-PLANK_ROTATION_JITTER_DEG, PLANK_ROTATION_JITTER_DEG))
		planks[i] = p
	layout["plank_pos"] = planks


## Affiche les jetons Fortune/Trésor à leur position mémorisée (layout[positions_key])
## et les enregistre comme objets déplaçables.
func _place_special_tokens(kind: String, texture: Texture2D, layout: Dictionary, positions_key: String) -> void:
	var positions: Array = layout.get(positions_key, [])
	var icon_size_local: Vector2 = _texture_size_to_local(SPECIAL_ICON_SIZE)
	for i in range(positions.size()):
		var pixel := Vector2(positions[i][0], positions[i][1])
		var anchor: Vector2 = _texture_to_local(pixel) - icon_size_local / 2.0
		var nodes := _add_token_with_thickness(texture, anchor, icon_size_local)
		_draggable_items.append({
			"kind": kind, "index": i,
			"rect": Rect2(anchor, icon_size_local),
			"nodes": nodes,
		})


## Empile plusieurs copies assombries du jeton, décalées vers le bas-gauche
## (DEPTH_DIRECTION), puis la copie en couleur normale au-dessus : donne une
## petite épaisseur au jeton au lieu d'un sprite plat. Retourne la liste des
## nodes créés (utile pour les déplacer ensemble pendant un glisser-déposer).
func _add_token_with_thickness(texture: Texture2D, anchor: Vector2, icon_size: Vector2) -> Array:
	var nodes: Array = []
	var step: Vector2 = UiTheme.DEPTH_DIRECTION * (TOKEN_THICKNESS_PX / float(TOKEN_THICKNESS_LAYERS))
	for layer in range(TOKEN_THICKNESS_LAYERS, 0, -1):
		var edge := TextureRect.new()
		edge.texture = texture
		edge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		edge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		edge.size = icon_size
		edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		edge.modulate = Color(1, 1, 1).darkened(TOKEN_EDGE_DARKEN)
		resource_slots.add_child(edge)
		edge.position = anchor + step * layer
		nodes.append(edge)

	var top := TextureRect.new()
	top.texture = texture
	top.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	top.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	top.size = icon_size
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	resource_slots.add_child(top)
	top.position = anchor
	nodes.append(top)
	return nodes


## Affiche les planches de coque du joueur à leur position, couleur et
## rotation mémorisées (layout["plank_pos"] = [x, y, teinte, rotation]).
func _place_hull_planks_from_layout(layout: Dictionary) -> void:
	var positions: Array = layout.get("plank_pos", [])
	var size_local: Vector2 = _texture_size_to_local(PLANK_SIZE)
	for i in range(positions.size()):
		var p: Array = positions[i]
		var pixel := Vector2(p[0], p[1])
		var color_shift: float = p[2]
		var rotation_deg: float = p[3]
		var center: Vector2 = _texture_to_local(pixel)
		var plank := _build_plank_icon(_wood_color_variant(color_shift), size_local)
		resource_slots.add_child(plank)
		plank.position = center
		plank.rotation_degrees = rotation_deg
		_draggable_items.append({
			"kind": "plank", "index": i,
			"rect": Rect2(center - size_local / 2.0, size_local),
			"nodes": [plank],
		})


## Variation de teinte autour du brun bois de base, pour que les planches ne
## soient pas des clones parfaitement identiques (bois naturel). `shift` est
## tiré une seule fois par planche puis mémorisé (voir _ensure_plank_style).
func _wood_color_variant(shift: float) -> Color:
	var base: Color = RESOURCE_CUBE_COLORS["wood"]
	return base.lightened(shift) if shift > 0.0 else base.darkened(-shift)


## Construit une planche en fausse perspective 3D (même technique que
## _build_cube_icon : toit + 2 parois extrudées dans DEPTH_DIRECTION), avec
## en plus des veines de bois et deux clous aux extrémités pour un rendu
## plus réaliste qu'un simple rectangle plat.
func _build_plank_icon(base_color: Color, plank_size: Vector2) -> Node2D:
	var half := plank_size / 2.0
	var top_left := Vector2(-half.x, -half.y)
	var top_right := Vector2(half.x, -half.y)
	var bottom_right := Vector2(half.x, half.y)
	var bottom_left := Vector2(-half.x, half.y)

	# Épaisseur proportionnelle à la petite dimension (planche fine), pas au
	# côté comme pour les cubes de ressource. On prend min(x, y) pour rester
	# correct que la planche soit affichée à l'horizontale ou à la verticale.
	var extrude: Vector2 = -UiTheme.DEPTH_DIRECTION * min(plank_size.x, plank_size.y) * CUBE_EXTRUDE_RATIO

	var top_color: Color = base_color.lightened(0.25)
	var left_wall_color: Color = base_color.darkened(0.15)
	var bottom_wall_color: Color = base_color.darkened(0.4)

	var plank := Node2D.new()

	var left_wall := Polygon2D.new()
	left_wall.polygon = PackedVector2Array([
		top_left, bottom_left, bottom_left + extrude, top_left + extrude
	])
	left_wall.color = left_wall_color
	plank.add_child(left_wall)

	var bottom_wall := Polygon2D.new()
	bottom_wall.polygon = PackedVector2Array([
		bottom_left, bottom_right, bottom_right + extrude, bottom_left + extrude
	])
	bottom_wall.color = bottom_wall_color
	plank.add_child(bottom_wall)

	var top_face := Polygon2D.new()
	top_face.polygon = PackedVector2Array([
		top_left + extrude, top_right + extrude, bottom_right + extrude, bottom_left + extrude
	])
	top_face.color = top_color
	plank.add_child(top_face)

	return plank


## Tire une position aléatoire dans le rectangle, en essayant de rester à au
## moins SPECIAL_TOKEN_MIN_DISTANCE des positions déjà choisies (échantillonnage
## par rejet). Si aucun essai ne satisfait la distance, garde le meilleur essai.
func _pick_spaced_position(rect_min: Vector2, rect_max: Vector2, existing: Array[Vector2]) -> Vector2:
	var best_pos := Vector2(randf_range(rect_min.x, rect_max.x), randf_range(rect_min.y, rect_max.y))
	var best_score := -1.0
	for attempt in range(SPECIAL_TOKEN_MAX_ATTEMPTS):
		var candidate := Vector2(randf_range(rect_min.x, rect_max.x), randf_range(rect_min.y, rect_max.y))
		if existing.is_empty():
			return candidate
		var min_dist := INF
		for p in existing:
			min_dist = min(min_dist, candidate.distance_to(p))
		if min_dist >= SPECIAL_TOKEN_MIN_DISTANCE:
			return candidate
		if min_dist > best_score:
			best_score = min_dist
			best_pos = candidate
	return best_pos


## Construit un cube en fausse perspective. La base (120x120, centrée sur la
## position donnée) N'EST PAS dessinée : elle touche le plateau, donc elle
## est cachée entre le plateau et le cube. On ne dessine que ce qui est
## réellement visible : le toit (translation exacte de la base, donc lui
## aussi un carré 120x120 non déformé) et les deux parois qui comblent la
## hauteur, dans le sens opposé à DEPTH_DIRECTION (cohérence avec les jetons).
func _build_cube_icon(base_color: Color, edge: float) -> Node2D:
	var half := edge / 2.0
	var top_left := Vector2(-half, -half)
	var top_right := Vector2(half, -half)
	var bottom_right := Vector2(half, half)
	var bottom_left := Vector2(-half, half)

	var extrude: Vector2 = -UiTheme.DEPTH_DIRECTION * edge * CUBE_EXTRUDE_RATIO

	var roof_color: Color = base_color.lightened(0.35)
	var left_wall_color: Color = base_color.darkened(0.15)
	var bottom_wall_color: Color = base_color.darkened(0.4)

	var cube := Node2D.new()

	# Paroi gauche : entre le bord gauche de la base (caché) et le bord
	# gauche du toit.
	var left_wall := Polygon2D.new()
	left_wall.polygon = PackedVector2Array([
		top_left, bottom_left, bottom_left + extrude, top_left + extrude
	])
	left_wall.color = left_wall_color
	cube.add_child(left_wall)

	# Paroi basse : entre le bord bas de la base (caché) et le bord bas du
	# toit. C'est la face la plus proche du joueur, donc la plus sombre.
	var bottom_wall := Polygon2D.new()
	bottom_wall.polygon = PackedVector2Array([
		bottom_left, bottom_right, bottom_right + extrude, bottom_left + extrude
	])
	bottom_wall.color = bottom_wall_color
	cube.add_child(bottom_wall)

	# Toit : simple translation de la base par l'extrusion, donc un carré
	# 120x120 non déformé lui aussi (juste décalé), pas la base elle-même.
	var roof := Polygon2D.new()
	roof.polygon = PackedVector2Array([
		top_left + extrude, top_right + extrude, bottom_right + extrude, bottom_left + extrude
	])
	roof.color = roof_color
	cube.add_child(roof)

	return cube


## Convertit une position en pixels de l'image d'origine vers une position
## locale dans BoardTexture / ResourceSlots (même rect), quelle que soit la
## taille affichée à l'écran.
func _texture_to_local(pixel_pos: Vector2) -> Vector2:
	if board_texture.texture == null:
		return pixel_pos
	return pixel_pos * (board_texture.size / board_texture.texture.get_size())


## Convertit une position locale (écran, dans ResourceSlots) vers sa position
## en pixels de l'image d'origine. Inverse de _texture_to_local, utilisée
## pour mémoriser la position d'un objet après un glisser-déposer.
func _local_to_texture(local_pos: Vector2) -> Vector2:
	if board_texture.texture == null:
		return local_pos
	return local_pos / (board_texture.size / board_texture.texture.get_size())


## Convertit une longueur (ex: un côté de cube) en pixels image vers sa
## longueur équivalente à l'écran.
func _texture_length_to_local(length_px: float) -> float:
	if board_texture.texture == null:
		return length_px
	var scale_factor: Vector2 = board_texture.size / board_texture.texture.get_size()
	return length_px * (scale_factor.x + scale_factor.y) / 2.0


## Convertit une taille (Vector2) en pixels image vers sa taille écran.
func _texture_size_to_local(size_px: Vector2) -> Vector2:
	if board_texture.texture == null:
		return size_px
	return size_px * (board_texture.size / board_texture.texture.get_size())


func _on_blocker_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		visible = false


## Détecte le clic initial sur un objet déplaçable de l'inventaire.
func _on_resource_slots_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_try_start_drag(event.position)


func _try_start_drag(local_pos: Vector2) -> void:
	for i in range(_draggable_items.size() - 1, -1, -1):
		var item: Dictionary = _draggable_items[i]
		var rect: Rect2 = item["rect"]
		if rect.has_point(local_pos):
			_dragging_item = item
			_drag_offset = local_pos - rect.position
			_drag_active = true
			for n in item["nodes"]:
				n.z_index = 100
			return


## Écoute globale (indépendante des limites de ResourceSlots) pendant un
## glisser-déposer, pour ne pas perdre le suivi si la souris sort vite de la
## zone. Ne fait rien tant qu'aucun glisser-déposer n'est en cours.
func _input(event: InputEvent) -> void:
	if not _drag_active:
		return
	if event is InputEventMouseMotion:
		_update_drag_position(resource_slots.get_local_mouse_position())
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_finish_drag(resource_slots.get_local_mouse_position())
		get_viewport().set_input_as_handled()


func _update_drag_position(local_pos: Vector2) -> void:
	var item: Dictionary = _dragging_item
	var rect: Rect2 = item["rect"]
	var new_top_left: Vector2 = local_pos - _drag_offset

	if item["kind"] != "resource":
		var rect_min: Vector2
		var rect_max: Vector2
		match item["kind"]:
			"treasure":
				rect_min = TREASURE_RECT_MIN
				rect_max = TREASURE_RECT_MAX
			"fortune":
				rect_min = FORTUNE_RECT_MIN
				rect_max = FORTUNE_RECT_MAX
			"plank":
				rect_min = PLANK_RECT_MIN
				rect_max = PLANK_RECT_MAX
		var local_min: Vector2 = _texture_to_local(rect_min)
		var local_max: Vector2 = _texture_to_local(rect_max)
		new_top_left.x = clamp(new_top_left.x, local_min.x, max(local_min.x, local_max.x - rect.size.x))
		new_top_left.y = clamp(new_top_left.y, local_min.y, max(local_min.y, local_max.y - rect.size.y))

	var delta: Vector2 = new_top_left - rect.position
	rect.position = new_top_left
	item["rect"] = rect
	for n in item["nodes"]:
		n.position += delta


func _finish_drag(local_pos: Vector2) -> void:
	_update_drag_position(local_pos)
	var item: Dictionary = _dragging_item
	_drag_active = false
	_dragging_item = {}
	if item.is_empty() or _current_player.is_empty():
		return

	var layout: Dictionary = _current_player["inventory_layout"]
	match item["kind"]:
		"resource":
			_finish_resource_drag(item, layout)
		"treasure":
			_finish_free_drag(item, layout, "treasure_pos")
		"fortune":
			_finish_free_drag(item, layout, "fortune_pos")
		"plank":
			_finish_free_drag(item, layout, "plank_pos")

	GameFlow.save_players()
	_refresh_resource_display(_current_player)


## Ressource classique : on l'accroche au slot fixe le plus proche du point
## de dépose. Si ce slot contient déjà une autre ressource, les deux
## échangent leur place (swap) ; sinon la ressource déplacée occupe le slot
## libre. Un dépôt hors zone/inchangé n'a aucun effet (retour au refresh).
func _finish_resource_drag(item: Dictionary, layout: Dictionary) -> void:
	var slots: Array = layout["resource_slots"]
	var from_index: int = item["index"]
	var rect: Rect2 = item["rect"]
	var center: Vector2 = rect.position + rect.size / 2.0

	var nearest_index := -1
	var nearest_dist := INF
	for i in range(RESOURCE_SLOT_PIXELS.size()):
		var slot_center: Vector2 = _texture_to_local(RESOURCE_SLOT_PIXELS[i])
		var d := center.distance_to(slot_center)
		if d < nearest_dist:
			nearest_dist = d
			nearest_index = i

	if nearest_index == -1 or nearest_index == from_index:
		return

	var tmp = slots[nearest_index]
	slots[nearest_index] = slots[from_index]
	slots[from_index] = tmp
	layout["resource_slots"] = slots


## Jeton Fortune/Trésor ou planche : la position (déjà bornée à la zone dans
## _update_drag_position) est simplement mémorisée.
func _finish_free_drag(item: Dictionary, layout: Dictionary, key: String) -> void:
	var positions: Array = layout[key]
	var rect: Rect2 = item["rect"]
	var center: Vector2 = rect.position + rect.size / 2.0
	var pixel := _local_to_texture(center)
	# On ne met à jour que x/y : les éventuels champs supplémentaires (ex :
	# teinte et rotation des planches, aux index 2 et 3) sont conservés tels
	# quels pour ne pas régénérer l'aspect de l'objet à chaque déplacement.
	var entry: Array = positions[item["index"]]
	entry[0] = pixel.x
	entry[1] = pixel.y
	positions[item["index"]] = entry
	layout[key] = positions
