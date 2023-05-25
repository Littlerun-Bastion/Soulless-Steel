extends Goal


# relax will always be available
func is_valid(_agent) -> bool:
	return true


# The lower the priority, the less likely it will be chosen
func priority(_agent) -> int:
	return 0
