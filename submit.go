package main

import (
	"os"
	"fmt"
	"time"
	"flag"
	"strings"
	"flapjack"
)

func main() {

	entity   := flag.String("e", "", "Entity name")
	check    := flag.String("c", "", "Check name")
	state    := flag.String("s", "", "Current state")
	summary  := flag.String("u", "", "Summary of event")
	debug    := flag.Bool("v", false, "Turn on debugging messages")
	address  := flag.String("a", "localhost:6380", "Redis instance to connect to")
	database := flag.Int("d", 0, "Redis database to connect to")
	flag.Parse()

	if *debug {
		fmt.Println("entity:", *entity)
		fmt.Println("check:", *check)
		fmt.Println("state:", *state)
		fmt.Println("summary:", *summary)
	}

	addr := strings.Split(*address, ":")
	if len(addr) != 2 {
		fmt.Println("Error: invalid address specified:", *address)
		fmt.Println("Should be in format `addr:port` (e.g. 127.0.0.1:6380)")
		os.Exit(1)
	}

	transport, err := flapjack.Dial(*address, *database)
	if err != nil {
		fmt.Println("Error: couldn't connect to Redis:", err)
		os.Exit(1)
	}

	event := flapjack.Event{
		Entity: 	*entity,
		Check: 		*check,
		Type:		"service",
		State:		*state,
		Summary:	*summary,
		Time:		time.Now().Unix(),
	}

	_, err = transport.Send(event)
	if err != nil {
		fmt.Println("Error: couldn't send event:", err)
		os.Exit(1)
	}
}
