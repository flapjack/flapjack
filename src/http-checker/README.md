# Pandik http-checker

Monitoring tool for web services. Self-hosted [pingdom](http://pingdom.com) alternative.

Original project: https://github.com/oguzbilgic/pandik
I have a pull request open (https://github.com/michaelneale/pandik)
Placing the code here for review and possible inclusion. 

This is tweaked from the original "pandik"  to work with flapjack events. 
Needs to access flapjacks redis (as specified in the address field).

"url" is the event, roughly, and "name" is the "check" - or something. 


## Installation 

Clone and go get -d & go build
./http-checker

## Configuration

Pandik uses `~/.pandik.json` file for configuration by default, but you can overwrite this by using 
`-c` command file with path to your configuration file. Here is a sample configuration file: 

```json
{

  "monitors": [
    {
      "type": "http-status",
      "url": "http://localhost:8000",
      "name": "My website healthcheck",
      "freq": "10s",
      "timeout": "2s"
    }

  ],
  
  "notifiers": [
    {
      "type": "flapjack",
      "address" : "boot2docker:6380"
    }
  ]
}
```

## Usage

Locate your configuration file and run the comman bellow

```bash
$ pandik -c /path/to/configuration.json
```

To run pandik as a deamon on your system use the `-d` flag

```bash
$ pandik -d -c /path/to/configuration.json
```

By default pandik uses `~/.pandik.log` for deamon's log file, but this can be overwritten by `-l` flag

```bash
$ pandik -d -l /path/to/log.file -c /path/to/configuration.json
```
    
## License

The MIT License (MIT)
