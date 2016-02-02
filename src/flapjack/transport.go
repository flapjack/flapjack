package flapjack

import (
	"encoding/json"
	"github.com/garyburd/redigo/redis"
)

// Transport is a representation of a Redis connection.
type Transport struct {
	Address    string
	Database   int
	Connection redis.Conn
}

// Dial establishes a connection to Redis, wrapped in a Transport.
func Dial(address string, database int) (Transport, error) {
	// Connect to Redis
	conn, err := redis.Dial("tcp", address)
	if err != nil {
		return Transport{}, err
	}

	// Switch database
	conn.Do("SELECT", database)

	transport := Transport{
		Address:    address,
		Database:   database,
		Connection: conn,
	}
	return transport, nil
}

// Send takes an event and sends it over a transport.
func (t Transport) Send(event Event) (interface{}, error) {
	err := event.IsValid()
	if err != nil {
		return nil, err
	}

	data, _ := json.Marshal(event)
	reply, err := t.Connection.Do("LPUSH", "events", data)
	if err != nil {
		return nil, err
	}

	// required for Flapjack v2 -- if the broker is split out as a separate
	// project, this will need to be optional
	_, err = t.Connection.Do("LPUSH", "events_actions", "+")
	if err != nil {
		return nil, err
	}

	return reply, nil
}
