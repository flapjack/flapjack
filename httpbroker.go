package main

import (
	"fmt"
	"log"
	"os"
	"io/ioutil"
	"time"
	"net/http"
	"flapjack"
	"encoding/json"
	"gopkg.in/alecthomas/kingpin.v1"
)

// handler caches
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

	// Populate a time if none has been set.
	if state.Time == 0 {
		state.Time = time.Now().Unix()
	}

	if len(state.Type) == 0 {
		state.Type = "service"
	}

	newState <- state

	json, _ := json.Marshal(state)
	log.Printf("Caching event: %s\n", json)
	fmt.Fprintf(w, "Caching event: %s\n", json)
}

// cacheState stores a cache of event state to be sent to Flapjack.
// The event state is queried later when submitting events periodically
// to Flapjack.
func cacheState(newState chan flapjack.Event, state map[string]flapjack.Event) {
	for ns := range newState {
		key := ns.Entity + ":" + ns.Check
		state[key] = ns
	}
}

// submitCachedState periodically samples the cached state, sends it to Flapjack.
func submitCachedState(states map[string]flapjack.Event, config Config) {
	transport, err := flapjack.Dial(config.Server, config.Database)
	if err != nil {
		fmt.Printf("Error: %s\n", err)
		os.Exit(1)
	}

	for {
		log.Printf("Number of cached states: %d\n", len(states))
		for id, state := range(states) {
			event := flapjack.Event{
				Entity:  state.Entity,
				Check:   state.Check,
				Type:    state.Type,
				State:   state.State,
				Summary: state.Summary,
				Time:    time.Now().Unix(),
			}
			if config.Debug {
				log.Printf("Sending event data for %s\n", id)
			}
			transport.Send(event)
		}
		time.Sleep(config.Interval)
	}
}

var (
	server		= kingpin.Flag("server", "Redis server to connect to (default localhost:6380)").Default("localhost:6380").String()
	database	= kingpin.Flag("database", "Redis database to connect to (default 0)").Int() // .Default("13").Int()
	interval	= kingpin.Flag("interval", "How often to submit events (default 10s)").Default("10s").Duration()
	debug		= kingpin.Flag("debug", "Enable verbose output (default false)").Bool()
)

type Config struct {
	Server		string
	Database	int
	Interval	time.Duration
	Debug		bool
}

func main() {
	kingpin.Version("0.0.1")
	kingpin.Parse()

	config := Config{
		Server: 	*server,
		Database: 	*database,
		Interval: 	*interval,
		Debug:		*debug,
	}
	if config.Debug {
		log.Printf("Booting with config: %+v\n", config)
	}

	newState := make(chan flapjack.Event)
	state := map[string]flapjack.Event{}

	go cacheState(newState, state)
	go submitCachedState(state, config)

	http.HandleFunc("/", func (w http.ResponseWriter, r *http.Request) {
		handler(newState, w, r)
	})
	http.ListenAndServe(":8080", nil)
}
