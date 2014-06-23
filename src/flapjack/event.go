package flapjack

type Event struct {
	Entity	string `json:"entity"`
	Check	string `json:"check"`
	Type	string `json:"type"`
	State	string `json:"state"`
	Summary	string `json:"summary"`
	Time	int64  `json:"time"`
}

func (e Event) IsValid() (bool, string) {
	if len(e.Entity)  == 0 { return false, "No entity" }
	if len(e.Check)   == 0 { return false, "No check" }
	if len(e.State)   == 0 { return false, "No state" }
	if len(e.Summary) == 0 { return false, "No summary" }
	return true, "ok"
}

