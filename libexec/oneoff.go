package main

import (
	"encoding/json"
	"flapjack"
	"fmt"
	"gopkg.in/alecthomas/kingpin.v2"
	"os"
	"strings"
	"time"
)

var (
	app = kingpin.New("oneoff", "Submits a single event to Flapjack.")

	flapjack_version = app.Flag("flapjack-version", "Flapjack version being delivered to (1 or 2)").Default("2").Int()

	entity   = app.Arg("entity", "Entity name").Required().String()
	check    = app.Arg("check", "Check name").Required().String()
	state    = app.Arg("state", "Current state").Required().String()
	summary  = app.Arg("summary", "Summary of event").Required().String()
	debug    = app.Flag("debug", "Enable verbose output (default false)").Bool()
	server   = app.Flag("server", "Redis server to connect to").Default("localhost:6380").String()
	database = app.Flag("database", "Redis database to connect to").Default("0").Int()
	queue    = app.Flag("queue", "Flapjack event queue name to use").Default("events").String()
)

func main() {
	app.Version("0.0.2")
	app.Writer(os.Stdout) // direct help to stdout
	kingpin.MustParse(app.Parse(os.Args[1:]))
	app.Writer(os.Stderr) // ... but ensure errors go to stderr

	if *debug {
		fmt.Println("Flapjack version:", *flapjack_version)

		fmt.Println("Entity:", *entity)
		fmt.Println("Check:", *check)
		fmt.Println("State:", *state)
		fmt.Println("Summary:", *summary)
		fmt.Println("Debug:", *debug)
		fmt.Println("Server:", *server)
		fmt.Println("Database:", *database)
		fmt.Println("Queue:", *queue)
	}

	addr := strings.Split(*server, ":")
	if len(addr) != 2 {
		fmt.Println("Error: invalid address specified:", *server)
		fmt.Println("Should be in format `addr:port` (e.g. 127.0.0.1:6380)")
		os.Exit(1)
	}

	event := flapjack.Event{
		Entity:  *entity,
		Check:   *check,
		Type:    "service",
		State:   *state,
		Summary: *summary,
		Time:    time.Now().Unix(),
	}

	if *debug {
		data, _ := json.Marshal(event)
		fmt.Printf("Event data: %s\n", data)
	}

	transport, err := flapjack.Dial(*server, *database)
	if *debug {
		fmt.Printf("Transport: %+v\n", transport)
	}
	if err != nil {
		fmt.Println("Error: couldn't connect to Redis:", err)
		os.Exit(1)
	}

	reply, err := transport.SendVersionQueue(event, *flapjack_version, *queue)

	if *debug {
		fmt.Println("Reply from Redis:", reply)
	}
	if err != nil {
		fmt.Println("Error: couldn't send event:", err)
		os.Exit(1)
	}
}
