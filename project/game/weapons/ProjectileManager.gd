extends Node

enum TYPE {INSTANT, REGULAR}

const REGULAR = preload("res://game/weapons/RegularProjectile.tscn")

func create(mecha, args):
	var projectile_data = args.weapon_data
	var data = {
		"create_node": false,
		"node": null,
	}
	
	if projectile_data.type == TYPE.INSTANT:
		pass
	
	elif projectile_data.type == TYPE.REGULAR:
		var projectile = REGULAR.instance()
		projectile.setup(mecha, args)
		data.create_node = true
		data.node = projectile
	
	return data
