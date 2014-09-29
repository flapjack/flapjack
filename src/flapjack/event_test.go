package flapjack

import "testing"

func TestValidationFails(t *testing.T) {
	event := Event{}
	err := event.IsValid()

	if err == nil {
		t.Error("Expected validation to fail.")
	}
}

func TestValidationPasses(t *testing.T) {
	event := Event{
		Entity:  "hello",
		Check:   "world",
		State:   "ok",
		Summary: "hello world",
	}
	err := event.IsValid()

	if err != nil {
		t.Error("Expected validation to pass, got:", err)
	}
}
