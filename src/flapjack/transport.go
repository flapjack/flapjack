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
func (t Transport) Send(event Event, flapjackVersion int, list string) (interface{}, error) {
	err := event.IsValid()
	if err != nil {
		return nil, err
	}

	data, _ := json.Marshal(event)
	reply, err := t.Connection.Do("LPUSH", list, data)
	if err != nil {
		return nil, err
	}

	if flapjackVersion >= 2 {
		_, err := t.Connection.Do("LPUSH", list+"_actions", "+")

		if err != nil {
			return nil, err
		}
	}

	return reply, nil
}

func (t Transport) Close() (interface{}, error) {
	reply, err := t.Connection.Do("QUIT")
	if err != nil {
		return nil, err
	}

	return reply, nil
}
