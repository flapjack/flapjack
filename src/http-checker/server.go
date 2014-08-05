package main

type Server struct {
	Config  *Config
	LogChan chan *Log

	Monitors  []*Monitor
	Notifiers []Notifier
}

func NewServer(config *Config) (*Server, error) {
	s := &Server{
		Config:  config,
		LogChan: make(chan *Log, 50),
	}

	for _, monitorConf := range config.MonitorConfs {
		monitor, err := NewMonitor(monitorConf)
		if err != nil {
			return nil, err
		}

		s.Monitors = append(s.Monitors, monitor)
	}

	s.Notifiers = append(s.Notifiers, NotifyViaStderr)
	for _, notifierConf := range config.NotifierConfs {
		notifier, err := NewNotifier(notifierConf)
		if err != nil {
			return nil, err
		}

		s.Notifiers = append(s.Notifiers, notifier)
	}

	return s, nil
}

func (s *Server) Loop() {
	for _, monitor := range s.Monitors {
		go monitor.Watch(s.LogChan)
	}

	for {
		log := <-s.LogChan
		for _, notifier := range s.Notifiers {
			notifier(log)
		}
	}
}
