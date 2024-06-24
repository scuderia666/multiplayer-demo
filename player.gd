extends CharacterBody3D

@onready var nametag = $nametag

var nickname = ""
var falling = false
var jump = false

var movement_x = 0
var movement_z = 0

func _ready():
	nametag.text = nickname
