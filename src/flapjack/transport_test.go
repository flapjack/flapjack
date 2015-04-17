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

func TestSendSucceeds(t *testing.T) {
	transport, _ := Dial("localhost:6379", 9)
	event := Event{
		Entity:  "hello",
		Check:   "world",
		State:   "ok",
		Summary: "hello world",
	}

	_, err := transport.Send(event)
	if err != nil {
		t.Error("Error upon sending event: %v", err)
	}

}

func TestSendFails(t *testing.T) {
	transport, _ := Dial("localhost:6379", 9)
	event := Event{}

	_, err := transport.Send(event)
	if err == nil {
		t.Error("Expected error upon sending event: %v", err)
	}
}
