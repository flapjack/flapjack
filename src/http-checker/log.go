package main

import (
	"sort"
	"time"
)

type Log struct {
	Up       bool
	Time     time.Time
	Message  string
	Monitor  *Monitor
	Duration int64
}

func NewLog(up bool, message string, duration int64) *Log {
	return &Log{up, time.Now(), message, nil, duration}
}

type Logs []*Log

func (logs Logs) Len() int {
	return len(logs)
}

func (logs Logs) Swap(i int, j int) {
	logs[i], logs[j] = logs[j], logs[i]
}

func (logs Logs) Less(i int, j int) bool {
	return logs[i].Time.Before(logs[j].Time)
}

func (logs *Logs) Add(log *Log) {
	*logs = append(*logs, log)
	sort.Sort(logs)
}

func (logs Logs) Last() *Log {
	return logs[logs.Len()-1]
}
