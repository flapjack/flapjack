package main

import (
	"time"
)

type MonitorConf struct {
	Type    string
	Url     string
	Freq    string
	Name    string
	Timeout string
	Data    map[string]string
}

type Monitor struct {
	Conf    *MonitorConf
	Checker Checker
	Logs    Logs
}

func NewMonitor(conf *MonitorConf) (*Monitor, error) {
	checker, err := GetChecker(conf.Type)
	if err != nil {
		return nil, err
	}

	return &Monitor{conf, checker, nil}, nil
}

func (m *Monitor) Watch(logChan chan *Log) {
	for {
		log := m.Checker(m.Conf)
		log.Monitor = m

		logChan <- log

		m.Logs.Add(log)

		nextCheck, _ := time.ParseDuration(m.Conf.Freq)
		time.Sleep(nextCheck)
	}
}
