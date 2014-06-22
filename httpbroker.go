package main

import (
    "fmt"
	"os"
	"time"
    "net/http"
	"flapjack"
	"github.com/garyburd/redigo/redis"
)

func handler(w http.ResponseWriter, r *http.Request) {
	address  := "localhost:6379"
	database := 13
	entity   := "httpbroker"
	check    := "foo"
	state    := "ok"
	summary  := "event from httpbroker"

	conn, err := redis.Dial("tcp", address) // Connect to Redis
	if err != nil {
		fmt.Printf("Error: %s\n", err)
		os.Exit(1)
	}
	conn.Do("SELECT", database) // Switch database

	event := &flapjack.Event{
		Entity: 	entity,
		Check: 		check,
		Type:		"service",
		State:		state,
		Summary:	summary,
		Time:		time.Now().Unix(),
	}
	event.Submit(conn)

	fmt.Printf("%+v\n", event)
    fmt.Fprintf(w, "Posting event to Flapjack\n")
}

func main() {
    http.HandleFunc("/", handler)
    http.ListenAndServe(":8080", nil)
}
