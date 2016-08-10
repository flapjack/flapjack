package main

import (
	"errors"
	"log"
)

type Notifier func(*Log)

type NotifierConf struct {
	Type    string
	Address string
}

func NewNotifier(nc *NotifierConf) (Notifier, error) {
	switch nc.Type {
	case "stderr":
		return NotifyViaStderr, nil
	case "flapjack":
		return NotifyFlapjackRedis(nc), nil
	}

	return nil, errors.New("not suppported notifier: " + nc.Type)
}

func NotifyViaStderr(l *Log) {
	log.Printf("Monitor %s: %s\n", l.Monitor.Conf.Url, l.Message)
}
