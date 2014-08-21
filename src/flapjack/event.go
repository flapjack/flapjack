package flapjack

import "errors"

// Event is a basic representation of a Flapjack event.
// Find more at http://flapjack.io/docs/1.0/development/DATA_STRUCTURES
type Event struct {
	Entity  string `json:"entity"`
	Check   string `json:"check"`
	Type    string `json:"type"`
	State   string `json:"state"`
	Summary string `json:"summary"`
	Time    int64  `json:"time"`
}

// IsValid performs basic validations on the event data.
func (e Event) IsValid() error {
	// FIXME(auxesis): provide validation errors for each failure
	if len(e.Entity) == 0 {
		return errors.New("no entity")
	}
	if len(e.Check) == 0 {
		return errors.New("no check")
	}
	if len(e.State) == 0 {
		return errors.New("no state")
	}
	if len(e.Summary) == 0 {
		return errors.New("no summary")
	}
	return nil
}
