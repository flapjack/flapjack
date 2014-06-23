package flapjack

import (
	"encoding/json"
	"github.com/garyburd/redigo/redis"
)

type Transport struct {
	Address		string
	Database	int
	Connection	redis.Conn
}

// Dial a connection to Redis.
func Dial(address string, database int) (Transport,error) {
	// Connect to Redis
	conn, err := redis.Dial("tcp", address)
	if err != nil {
		return Transport{}, err
	}

	// Switch database
	conn.Do("SELECT", database)

	transport := Transport{
		Address: 	address,
		Database: 	database,
		Connection:	conn,
	}
	return transport, nil
}

// Provide a simple interface for sending events over a transport.
func (t Transport) Send(event Event) (interface{}) {
	valid, err := event.IsValid()
	if valid {
		data, _ := json.Marshal(event)
		reply, err := t.Connection.Do("LPUSH", "events", data)
		if err != nil {
			return err
		}

		return reply
	} else {
		return err
	}
}

