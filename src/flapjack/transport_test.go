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
	transport, err := Dial("localhost:6379", 9)
	if err != nil {
		t.Fatalf("Couldn't establish connection to testing Redis: %s", err)
	}
	event := Event{
		Entity:  "hello",
		Check:   "world",
		State:   "ok",
		Summary: "hello world",
	}

	_, err = transport.Send(event)
	if err != nil {
		t.Fatalf("Error when sending event: %s", err)
	}
}

func TestSendFails(t *testing.T) {
	transport, err := Dial("localhost:0", 9)
	if err == nil {
		t.Fatal("Expected error when connecting to testing Redis, got none.")
	}
	event := Event{}

	_, err = transport.Send(event)
	if err == nil {
		t.Fatal("Expected error when sending event, got none.")
	}
}
