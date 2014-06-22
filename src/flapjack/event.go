package flapjack

import (
	"log"
	"os"
	"github.com/garyburd/redigo/redis"
	"encoding/json"
)

type Event struct {
	Entity	string `json:"entity"`
	Check	string `json:"check"`
	Type	string `json:"type"`
	State	string `json:"state"`
	Summary	string `json:"summary"`
	Time	int64  `json:"time"`
}

func (e Event) IsValid() (bool, string) {
	if len(e.Entity)  == 0 { return false, "No entity" }
	if len(e.Check)   == 0 { return false, "No check" }
	if len(e.State)   == 0 { return false, "No state" }
	if len(e.Summary) == 0 { return false, "No summary" }
	return true, "ok"
}

func (e Event) Submit(conn redis.Conn) (interface{}) {
	valid, err := e.IsValid()
	if valid {
		data, _ := json.Marshal(e)
		reply, err := conn.Do("LPUSH", "events", data)
		if err != nil {
			log.Println(reply)
			log.Println(err)
			os.Exit(2)
		}

		return reply
	} else {
		log.Println("Error: Invalid event:", err)
		return false
	}
}

