package flapjack

import "testing"

func TestValidationFails(t *testing.T) {
	event := Event{}
	result, status := event.IsValid()

	if result != false {
		t.Error("Expected validation to fail.")
	}

	if status == "ok" {
		t.Error("status should not be ok")
	}
}

func TestValidationPasses(t *testing.T) {
	event := Event{
		Entity:		"hello",
		Check:		"world",
		State:		"ok",
		Summary:	"hello world",
	}
	result, status := event.IsValid()

	if result != true {
		t.Error("Expected validation to pass.")
	}

	if status != "ok" {
		t.Error("Expected no validation errors, got:", status)
	}
}
