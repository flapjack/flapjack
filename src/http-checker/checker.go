package main

import (
	"errors"
	"log"
	"net"
	"net/http"
	"time"
)

type Checker func(*MonitorConf) *Log

func GetChecker(checkerType string) (Checker, error) {
	switch checkerType {
	case "http-status":
		return checkHTTPStatus, nil
	}

	return nil, errors.New("not suppported checker: " + checkerType)
}

func checkHTTPStatus(mc *MonitorConf) *Log {

	var timeout, err = time.ParseDuration(mc.Timeout) // time.Duration(2 * time.Second)
	if err != nil {
		log.Printf("Defaulting to 60s timeout. Configured was %s", mc.Timeout)
		timeout = time.Duration(60 * time.Second)
	}

	transport := http.Transport{
		Dial: func(network, addr string) (net.Conn, error) {
			return net.DialTimeout(network, addr, timeout)
		},
	}
	client := http.Client{
		Transport: &transport,
	}

	start := time.Now()
	resp, err := client.Head(mc.Url)
	elapsed := time.Now().UnixNano() - start.UnixNano()

	if err != nil {
		return NewLog(false, err.Error(), elapsed)
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		return NewLog(false, "Http status is "+resp.Status, elapsed)
	}

	return NewLog(true, "Http status code is 200", elapsed)
}
