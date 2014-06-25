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
	"github.com/go-martini/martini"
)

// State is a basic representation of a Flapjack event, with some extra field.
// The extra fields handle state expiry.
// Find more at https://github.com/flapjack/flapjack/wiki/DATA_STRUCTURES
type State struct {
	flapjack.Event
	TTL	int64  `json:"ttl"`
}

// handler caches
func CreateState(updates chan State, w http.ResponseWriter, r *http.Request) {
	var state State

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

	if state.TTL == 0 {
		state.TTL = 300
	}

	updates <- state

	json, _ := json.Marshal(state)
	message := "Caching state: %s\n"
	log.Printf(message, json)
	fmt.Fprintf(w, message, json)
}

// cacheState stores a cache of event state to be sent to Flapjack.
// The event state is queried later when submitting events periodically
// to Flapjack.
func cacheState(updates chan State, state map[string]State) {
	for ns := range updates {
		key := ns.Entity + ":" + ns.Check
		state[key] = ns
	}
}

// submitCachedState periodically samples the cached state, sends it to Flapjack.
func submitCachedState(states map[string]State, config Config) {
	transport, err := flapjack.Dial(config.Server, config.Database)
	if err != nil {
		fmt.Printf("Error: %s\n", err)
		os.Exit(1)
	}

	for {
		log.Printf("Number of cached states: %d\n", len(states))
		for id, state := range(states) {
			now := time.Now().Unix()
			event := flapjack.Event{
				Entity:  state.Entity,
				Check:   state.Check,
				Type:    state.Type,
				State:   state.State,
				Summary: state.Summary,
				Time:    now,
			}

			// Stale state sends UNKNOWNs
			if now - state.Time > state.TTL {
				log.Printf("State for %s is stale. Sending UNKNOWN.\n", id)
				event.State = "UNKNOWN"
				event.Summary = fmt.Sprintf("httpbroker: Cached state is stale (>%ds old)", state.TTL)
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
	port		= kingpin.Flag("port", "Address to bind HTTP server (default 3090)").Default("3090").OverrideDefaultFromEnvar("PORT").String()
	server		= kingpin.Flag("server", "Redis server to connect to (default localhost:6380)").Default("localhost:6380").String()
	database	= kingpin.Flag("database", "Redis database to connect to (default 0)").Int() // .Default("13").Int()
	interval	= kingpin.Flag("interval", "How often to submit events (default 10s)").Default("10s").Duration()
	debug		= kingpin.Flag("debug", "Enable verbose output (default false)").Bool()
)

type Config struct {
	Port		string
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
		Port: 		":" + *port,
	}
	if config.Debug {
		log.Printf("Booting with config: %+v\n", config)
	}

	updates := make(chan State)
	state := map[string]State{}

	go cacheState(updates, state)
	go submitCachedState(state, config)

	m := martini.Classic()
	m.Group("/state", func(r martini.Router) {
		r.Post("", func(res http.ResponseWriter, req *http.Request) {
			CreateState(updates, res, req)
		})
		r.Get("", func() []byte {
			data, _ := json.Marshal(state)
			return data
		})
	})

	log.Fatal(http.ListenAndServe(config.Port, m))
}
