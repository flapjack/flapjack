package main

import (
	"os"
	"fmt"
	"log"
	"time"
	"flag"
	"unicode"
	"strings"
	"flapjack"
	"github.com/garyburd/redigo/redis"
)

func main() {

	entity   := flag.String("e", "", "Entity name")
	check    := flag.String("c", "", "Check name")
	state    := flag.String("s", "", "Current state")
	summary  := flag.String("u", "", "Summary of event")
	interval := flag.String("i", "0s", "How often event should be submitted e.g. 1s, 20ms")
	debug    := flag.Bool("v", false, "Turn on debugging messages")
	address  := flag.String("a", "localhost:6380", "Redis instance to connect to")
	database := flag.Int("d", 0, "Redis database to connect to")
	flag.Parse()

	if *debug {
		fmt.Println("entity:", *entity)
		fmt.Println("check:", *check)
		fmt.Println("state:", *state)
		fmt.Println("summary:", *summary)
		fmt.Println("interval:", *interval)
	}

	addr := strings.Split(*address, ":")
	if len(addr) != 2 {
		fmt.Println("Error: invalid address specified:", *address)
		fmt.Println("Should be in format `addr:port` (e.g. 127.0.0.1:6380)")
		os.Exit(1)
	}

	conn, err := redis.Dial("tcp", *address) // Connect to Redis
	if err != nil {
		fmt.Printf("Error: %s\n", err)
		os.Exit(1)
	}
	conn.Do("SELECT", *database) // Switch database

	event := &flapjack.Event{
		Entity: 	*entity,
		Check: 		*check,
		Type:		"service",
		State:		*state,
		Summary:	*summary,
		Time:		time.Now().Unix(),
	}
	event.Submit(conn) // Submit first event

	// Determine the interval to submit events
	i := *interval
	if !unicode.IsLetter(rune(i[(len(i) - 1)])) {
		i += "s"
	}
	_interval, _ := time.ParseDuration(i)

	if _interval > 0 {
		// Loop, submit, delay by interval
		for {
			reply := event.Submit(conn)
			if *debug {
				log.Println("Queue length", reply)
				log.Println("Sleeping for", _interval)
			}
			time.Sleep(_interval)
		}
	}

}
