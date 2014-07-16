package flapjack

import "testing"

func TestDialFails(t *testing.T) {
	address := "localhost:55555" // non-existent Redis server
	database := 0
	_, err := Dial(address, database)

	if err == nil {
		t.Error("Dial should fail")
	}
}

// TODO(auxesis): add test for sending and receiving Events
