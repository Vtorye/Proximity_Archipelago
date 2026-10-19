extends Workplace
class_name World1Workplace


func work_complete(_human: Node2D) -> void:
	print("worked at {name}".format({"name": name}))
