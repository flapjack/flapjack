package main

import (
	"flag"
	"log"
	"os"
	"os/user"
	"path"
)

func main() {
	usr, err := user.Current()
	if err != nil {
		log.Fatal(err)
	}

	configFilePath := flag.String("c", path.Join(usr.HomeDir, ".pandik.json"), "Configuration file")
	logFilePath := flag.String("l", path.Join(usr.HomeDir, ".pandik.log"), "Log file path for deamon")
	deamon := flag.Bool("d", false, "Run as a deamon")
	flag.Parse()

	if *deamon {
		args := []string{os.Args[0], "-c", *configFilePath}
		pid, err := deamonize(args, *logFilePath)
		if err != nil {
			log.Fatal(err)
		}

		println(pid)
		return
	}

	config, err := parseConfig(configFilePath)
	if err != nil {
		log.Fatal(err)
	}

	server, err := NewServer(config)
	if err != nil {
		log.Fatal(err)
	}

	server.Loop()
}

func deamonize(args []string, logFilePath string) (int, error) {
	cwd, err := os.Getwd()
	if err != nil {
		return -1, err
	}

	path, err := os.Readlink("/proc/self/exe")
	if err != nil {
		return -1, err
	}

	logFile, err := os.Create(logFilePath)
	if err != nil {
		return -1, err
	}

	procattr := os.ProcAttr{Dir: cwd, Env: os.Environ(), Files: []*os.File{logFile, logFile, logFile}}
	p, err := os.StartProcess(path, args, &procattr)
	if err != nil {
		return -1, err
	}

	pid := p.Pid

	err = p.Release()
	if err != nil {
		return -1, err
	}

	return pid, nil
}
