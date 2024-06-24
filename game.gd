extends Node

var ids = []

const SPEED = 5.0
const JUMP_VELOCITY = 8.5
var gravity = 20.0
const SPAWN_RANDOM := 9.0

var local_id
var local_character

var last_sent = {}
var last_received = {}

var rotation_last_sent

@onready var camera = get_node("SubViewportContainer/SubViewport/camera")

@onready var chatbox = get_node("hud/chatbox")
@onready var messagebox = get_node("hud/messagebox")
@onready var players = get_node("SubViewportContainer/SubViewport/players")

func _ready():
	local_id = multiplayer.get_unique_id()
	
	messagebox.connect("text_submitted", on_submit_message)
	get_node("SubViewportContainer").connect("gui_input", game_input)

	multiplayer.connect("server_disconnected", server_disconnected)

	if multiplayer.is_server():
		multiplayer.connect("peer_connected", on_client_join)
		multiplayer.connect("peer_disconnected", on_client_leave)

		last_sent[1] = {}
		spawn_player(1, Global.nickname, Vector3(0, 10, 0), false)
	
func broadcast_update(id, type, value, bypass = true):
	if last_sent[id].has(type):
		if last_sent[id][type] == value:
			return
	last_sent[id][type] = value
	for player_id in Global.players:
		if player_id == 1: continue
		if bypass and player_id == id: continue
		rpc_id(player_id, "client_receive_update", id, type, value)

@rpc("any_peer", "call_remote", "unreliable", 5)
func server_receive_update(type, value):
	var id = multiplayer.get_remote_sender_id()
	if last_received[id].has(type):
		if last_received[id][type] == value:
			return
	last_received[id][type] = value
	if type == "rotation":
		players.get_node(str(id)).rotation = value
	broadcast_update(id, type, value)

@rpc("any_peer", "call_local", "unreliable", 2)
func server_receive_movement_z(direction):
	var id = multiplayer.get_remote_sender_id()
	players.get_node(str(id)).movement_z = direction

@rpc("any_peer", "call_local", "unreliable", 3)
func server_receive_movement_x(direction):
	var id = multiplayer.get_remote_sender_id()
	players.get_node(str(id)).movement_x = direction

@rpc("any_peer", "call_local", "unreliable", 4)
func server_receive_jump():
	var id = multiplayer.get_remote_sender_id()

	if not players.get_node(str(id)).falling:
		players.get_node(str(id)).jump = true

@rpc("unreliable")
func client_receive_update(id, type, value):
	if type == "rotation":
		players.get_node(str(id)).rotation = value
	elif type == "position":
		players.get_node(str(id)).position = value

func send_update_to_server(type, value):
	if local_id != 1:
		rpc_id(1, "server_receive_update", type, value)

func send_jump():
	rpc_id(1, "server_receive_jump")

func send_movement_x(direction):
	rpc_id(1, "server_receive_movement_x", direction)

func send_movement_z(direction):
	rpc_id(1, "server_receive_movement_z", direction)

func send_rotation(rotation):
	if rotation == rotation_last_sent:
		return
	if local_id == 1:
		local_character.rotation = rotation
		broadcast_update(1, "rotation", rotation)
	else:
		send_update_to_server("rotation", rotation)
	rotation_last_sent = rotation

func game_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera.rotate_y(-event.relative.x * .005)
		local_character.rotation = camera.rotation
		send_rotation(local_character.rotation)

func process_input(delta):
	if messagebox.has_focus():
		if Input.is_action_just_pressed("enter") or Input.is_action_just_pressed("esc"):
			messagebox.release_focus()
		return
	elif Input.is_action_just_pressed("chat"):
		messagebox.call_deferred("grab_focus")

	if Input.is_action_just_pressed("esc"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if Input.is_action_just_pressed("up"):
		send_movement_z(-1)
	elif Input.is_action_just_released("up"):
		send_movement_z(0)

	if Input.is_action_just_pressed("down"):
		send_movement_z(1)
	elif Input.is_action_just_released("down"):
		send_movement_z(0)
	
	if Input.is_action_just_pressed("left"):
		send_movement_x(-1)
	elif Input.is_action_just_released("left"):
		send_movement_x(0)

	if Input.is_action_just_pressed("right"):
		send_movement_x(1)
	elif Input.is_action_just_released("right"):
		send_movement_x(0)

	if Input.is_action_pressed("space") and not local_character.falling:
		send_jump()

func _process(delta):
	if local_character != null:
		process_input(delta)

		camera.position = local_character.position + Vector3(0, 1.5, 0)

		for player in players.get_children():
			if not player.name == str(local_id):
				player.nametag.look_at(local_character.position, Vector3.UP, true)
				player.nametag.rotation.x = 0

	if multiplayer.is_server():
		process_server(delta)

func process_server(delta):
	for id in Global.players:
		var player = players.get_node(str(id))

		var moving = player.movement_z != 0 or player.movement_x != 0

		player.falling = not player.is_on_floor()

		if player.falling:
			player.velocity.y -= gravity * delta

		var direction = Vector3.ZERO

		if player.movement_z == -1:
			direction -= player.transform.basis.z
		elif player.movement_z == 1:
			direction += player.transform.basis.z
		if player.movement_x == -1:
			direction -= player.transform.basis.x
		elif player.movement_x == 1:
			direction += player.transform.basis.x

		if direction:
			player.velocity.x = direction.x * SPEED
			player.velocity.z = direction.z * SPEED
		else:
			player.velocity.x = move_toward(player.velocity.x, 0, SPEED)
			player.velocity.z = move_toward(player.velocity.z, 0, SPEED)

		if player.jump:
			player.velocity.y = JUMP_VELOCITY
			player.jump = false

		if player.position.y < -10:
			player.position = Vector3(0, 6, 0)

		player.move_and_slide()

		if moving or player.falling or player.jump:
			broadcast_update(id, "position", player.position, false)

func on_client_join(id):
	rpc_id(id, "request_login_data")

@rpc
func request_login_data():
	rpc_id(1, "receive_login_data", Global.nickname)

@rpc("any_peer")
func receive_login_data(nickname):
	var id = multiplayer.get_remote_sender_id()

	# get a random spawn position
	var pos := Vector2.from_angle(randf() * 2 * PI)
	var position = Vector3(pos.x * SPAWN_RANDOM * randf(), 5, pos.y * SPAWN_RANDOM * randf())

	last_sent[id] = {}
	last_received[id] = {}

	for player_id in Global.players:
		# introduce other players to player (no login message)
		rpc_id(id, "spawn_player", player_id, Global.player_names[player_id], players.get_node(str(player_id)).position, false)
		# introduce player to other players except host
		if player_id != 1:
			rpc_id(player_id, "spawn_player", id, nickname, position)

	# spawn player for host
	spawn_player(id, nickname, position)
	# spawn player for itself
	rpc_id(id, "spawn_player", id, nickname, position)

func on_client_leave(id):
	rpc("remove_client", id)

@rpc("call_local")
func remove_client(id):
	msg(Global.player_names[id] + " has left")
	remove_player(id)

@rpc
func spawn_player(id, nickname, position, login_message = true):
	var character = create_character(id, nickname, position)
	players.add_child(character)

	Global.players.append(id)
	Global.player_names[id] = nickname

	if id == local_id:
		character.nametag.visible = false
		local_character = character

	if login_message:
		msg(nickname + " has joined")

func create_character(id, nickname, position):
	var character = preload("res://player.tscn").instantiate()
	character.nickname = nickname
	character.position = position
	character.name = str(id)
	return character

func server_disconnected():
	Global.server_closed = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://menu.tscn")

func reset_hud():
	chatbox.text = ""
	messagebox.text = ""
	messagebox.release_focus()

	get_node("hud").visible = false
	get_node("SubViewportContainer").visible = false

func remove_players():
	for player in players.get_children():
		if player.name == str(local_id):
			player.set_process(false)
			player.set_process_input(false)
		player.queue_free()

func remove_player(id):
	if not players.has_node(str(id)):
		return
	players.get_node(str(id)).queue_free()
	Global.players.erase(id)
	Global.player_names.erase(id)
	Global.player_skins.erase(id)

func format(color, text):
	return "[color=" + color + "]" + text + "[/color]"

@rpc("any_peer", "call_local")
func chat(nick, message):
	msg("[b]" + format("blue", nick) + "[/b]: " + message)

func msg(message):
	chatbox.append_text(message + "\n")
	chatbox.scroll_to_line(chatbox.get_line_count()-1)

func on_submit_message(message):
	if message == "": return
	messagebox.text = ""
	chat.rpc(Global.nickname, message)
