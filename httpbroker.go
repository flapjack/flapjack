package main

import (
	"fmt"
	"os"
	"log"
	"io/ioutil"
	"time"
	"net/http"
	"flapjack"
	"github.com/garyburd/redigo/redis"
	"encoding/json"
)

func handler(newState chan flapjack.Event, w http.ResponseWriter, r *http.Request) {
	var state flapjack.Event

	body, err := ioutil.ReadAll(r.Body)
	if err != nil {
		message := "Error: Couldn't read request body: %s\n"
		log.Printf(message, err)
		fmt.Fprintf(w, message, err)
		return
	}

	err = json.Unmarshal(body, &state)
	if err != nil {
		message := "Error: Couldn't read request body: %s\n"
		log.Println(message, err)
		fmt.Fprintf(w, message, err)
		return
	}

	fmt.Printf("Caching event: %+v\n", state)

	// Populate a time if none has been set.
	if state.Time == 0 {
		state.Time = time.Now().Unix()
	}

	newState <- state
	fmt.Fprintf(w, "Caching event\n")
}

func cacheState(newState chan flapjack.Event, state map[string]flapjack.Event) {
	for ns := range newState {
		key := ns.Entity + ":" + ns.Check
		state[key] = ns
	}
}

func submitCachedState(states map[string]flapjack.Event) {
	address  := "localhost:6379"
	database := 13

	conn, err := redis.Dial("tcp", address) // Connect to Redis
	if err != nil {
		fmt.Printf("Error: %s\n", err)
		os.Exit(1)
	}
	conn.Do("SELECT", database) // Switch database

	interval := 1 * time.Second

	for {
		fmt.Printf("Number of cached states: %d\n", len(states))

		for id, state := range (states) {
			fmt.Printf("%s : %+v\n", id, state)

			event := &flapjack.Event{
				Entity:  state.Entity,
				Check:   state.Check,
				Type:    "service",
				State:   state.State,
				Summary: state.Summary,
				Time:    state.Time,
			}

			event.Submit(conn)
		}

		time.Sleep(interval)
	}
}

func main() {
	newState := make(chan flapjack.Event)
	state := map[string]flapjack.Event{}

	go cacheState(newState, state)
	go submitCachedState(state)

	http.HandleFunc("/", func (w http.ResponseWriter, r *http.Request) {
		handler(newState, w, r)
	})
	http.ListenAndServe(":8080", nil)
}
