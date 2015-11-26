#!/bin/bash

set -e

export GOPATH=$(pwd):$GOPATH

go get github.com/garyburd/redigo/redis
go get github.com/go-martini/martini
go get gopkg.in/alecthomas/kingpin.v2
go get github.com/oguzbilgic/pandik
mv bin/pandik libexec/httpchecker

if [ ! -z "$SKIPTESTS" ]; then
  go test flapjack
fi

go build -x -o libexec/httpbroker libexec/httpbroker.go
go build -x -o libexec/oneoff libexec/oneoff.go

if [ ! -z "$CROSSCOMPILE" ]; then
  for command in httpbroker oneoff; do
    GOOS=linux GOARCH=amd64 CGOENABLED=0 go build -x -o libexec/$command.linux_amd64 libexec/$command.go
    GOOS=linux GOARCH=386 CGOENABLED=0 go build -x -o libexec/$command.linux_386 libexec/$command.go
  done

  pushd src/github.com/oguzbilgic/pandik
  GOOS=linux GOARCH=amd64 CGOENABLED=0 go build -x -o httpchecker.linux_amd64
  GOOS=linux GOARCH=386 CGOENABLED=0 go build -x -o httpchecker.linux_386
  popd
  mv src/github.com/oguzbilgic/pandik/httpchecker.linux_amd64 libexec/httpchecker.linux_amd64
  mv src/github.com/oguzbilgic/pandik/httpchecker.linux_386 libexec/httpchecker.linux_386
fi


