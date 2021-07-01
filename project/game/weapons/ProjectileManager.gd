extends Node

enum TYPE {INSTANT, REGULAR}

const REGULAR = preload("res://game/weapons/RegularProjectile.tscn")

func create(mecha, projectile_data, pos, dir):
	var data = {
		"create_node": false,
		"node": null,
	}
	
	if projectile_data.type == TYPE.INSTANT:
		pass
	
	elif projectile_data.type == TYPE.REGULAR:
		var projectile = REGULAR.instance()
		projectile.setup(mecha, projectile_data, pos, dir)
		data.create_node = true
		data.node = projectile
	
	return data
