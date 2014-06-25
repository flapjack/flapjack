#!/bin/bash

set -e

export GOPATH=$(pwd):$GOPATH

go get github.com/garyburd/redigo/redis
go get github.com/go-martini/martini
go get gopkg.in/alecthomas/kingpin.v1

go test flapjack

go build -x -o libexec/httpbroker libexec/httpbroker.go
go build -x -o libexec/oneoff libexec/oneoff.go


if [ ! -z "$CROSSCOMPILE" ]; then
  for command in httpbroker oneoff; do
    GOOS=linux GOARCH=amd64 CGOENABLED=0 go build -x -o libexec/$command.linux_amd64 libexec/$command.go
    GOOS=linux GOARCH=386 CGOENABLED=0 go build -x -o libexec/$command.linux_386 libexec/$command.go
  done
fi
