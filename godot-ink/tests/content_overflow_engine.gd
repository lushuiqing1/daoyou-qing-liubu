extends "res://scripts/ink_engine.gd"
## Deliberately impossible cascade used only to verify transactional rollback.
func collapse(s: Dictionary, board: Array):
	for i in range(36): board[i] = tile(s, "red")
