extends CanvasLayer


func change_heatmap(heatmap):
	$Heatmap.material.set_shader_parameter("Colormap", heatmap)
