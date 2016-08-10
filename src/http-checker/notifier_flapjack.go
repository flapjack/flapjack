package main

import (
	flapjack "github.com/flapjack/flapjack/src/flapjack"
	"log"
	Url "net/url"
	"strconv"
)

func NotifyFlapjackRedis(nc *NotifierConf) func(*Log) {

	return func(l *Log) {

		Hurl, err := Url.Parse(l.Monitor.Conf.Url)
		if err != nil {
			log.Printf("Flapjack Notifier: Unable to parse %s", l.Monitor.Conf.Url)
			return
		}

		duration := " [" + strconv.FormatInt(l.Duration/1000000, 10) + "ms]"

		event := flapjack.Event{
			Entity:  Hurl.Host,
			Check:   l.Monitor.Conf.Name,
			State:   NewState(l),
			Summary: l.Message + duration,
			Type:    "service",
			Time:    l.Time.Unix(),
		}

		address := nc.Address
		database := 0 //production
		transport, err := flapjack.Dial(address, database)

		if err != nil {
			log.Printf("FlapjackNotifier: unable to connect to redis %s", address)
			return
		}

		transport.Send(event)

	}

}

func NewState(l *Log) string {
	ns := "critical"
	if l.Up {
		ns = "ok"
	}
	return ns
}
