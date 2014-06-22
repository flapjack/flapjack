#!/bin/bash

set -e

export GOPATH=$(pwd):$GOPATH

go get github.com/garyburd/redigo/redis

go build -x submit.go

if [ ! -z "$CROSSCOMPILE" ]; then
  GOOS=linux GOARCH=amd64 CGOENABLED=0 go build -x -o submit.linux_amd64 submit.go
  GOOS=linux GOARCH=386 CGOENABLED=0 go build -x -o submit.linux_386 submit.go
fi
