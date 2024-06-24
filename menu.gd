extends Node2D

func _ready():
	$connect_button.connect("pressed", join)
	$host_button.connect("pressed", host)

	if Global.server_closed:
		Global.server_closed = false
		error("Server closed")

func host():
	if $nick_input.text == "":
		error("Enter nickname")
		return
	var server = ENetMultiplayerPeer.new()
	var err = server.create_server(8910, 6)
	if err != OK:
		return
	multiplayer.multiplayer_peer = server
	start_game()

func join():
	if $ip_input.text == "":
		error("Enter ip address")
		return
	if $port_input.text == "":
		error("Enter port")
		return
	if $nick_input.text == "":
		error("Enter nickname")
		return
	var client = ENetMultiplayerPeer.new()
	var err = client.create_client($ip_input.text, int($port_input.text))
	if err != OK:
		return
	multiplayer.multiplayer_peer = client
	start_game()

func start_game():
	Global.nickname = get_node("nick_input").text
	get_tree().change_scene_to_file("res://game.tscn")

func error(msg):
	$error.set_text(msg)
	$error.popup_centered()
