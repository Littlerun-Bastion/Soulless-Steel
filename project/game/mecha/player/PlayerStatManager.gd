extends Node

var PlayerKills = []
var PlayerDowns = []
var PlayerHP = 0
var PlayerMaxHP = 0
var NumberofExtracts = 0
var RArmAmmo = 0
var LArmAmmo = 0
var RShoulderAmmo = 0
var LShoulderAmmo = 0
var RArmAmmoMax = 0
var LArmAmmoMax = 0
var RShoulderAmmoMax = 0
var LShoulderAmmoMax = 0
var RArmCost = 0
var LArmCost = 0
var RShoulderCost = 0
var LShoulderCost = 0
var Armor = 0
var Credits = 0
var ReloadCost = 0
var RepairCost = 0
var RepairedLastRound = true


func _ready():
	NumberofExtracts = 0
