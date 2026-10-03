extends "res://scripts/trial_session.gd"
## Controlled journal failure after ordinary progress has committed, test-only.
var fail_commit_once = true
func save() -> bool:
	if receipt_committed and fail_commit_once:
		fail_commit_once = false; last_error = "Injected final receipt-journal failure"; return false
	return super.save()
