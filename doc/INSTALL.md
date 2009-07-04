Dependencies
------------

Before installing Flapjack you will need to setup some dependencies.

### Setup dependencies (Ubuntu Hardy) ###

Add the following lines to `/etc/apt/sources.list`

    deb http://ppa.launchpad.net/ubuntu-ruby-backports/ubuntu hardy main
    deb http://ppa.launchpad.net/auxesis/ppa/ubuntu hardy main

Add GPG keys for the repos: 

    sudo apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 288BA53BCB7DA731

Update your package list:

    sudo apt-get update 

Install Ruby dependencies: 

    sudo apt-get install build-essential libsqlite3-dev

Install rubygems + beanstalkd:

    sudo apt-get install rubygems beanstalkd

Set `ENABLED=1` in `/etc/default/beanstalkd`.

Start beanstalkd: 

    sudo /etc/init.d/beanstalkd start


### Setup dependencies (everyone else) ###

Install the following software through your package manager or from source: 

 - beanstalkd (from [http://xph.us/software/beanstalkd/](http://xph.us/software/beanstalkd/))
 - libevent (from [http://monkey.org/~provos/libevent/](http://monkey.org/~provos/libevent/))
 - latest RubyGems (from [http://rubyforge.org/projects/rubygems/](http://rubyforge.org/projects/rubygems/))


## Installation ##

Add GitHub's RubyGems server to your Gem sources: 

    sudo gem sources -a http://gems.github.com

Install the Flapjack gem: 

    sudo gem install auxesis-flapjack

Then run the magic configuration script to set up init scripts: 

    sudo install-flapjack-systemwide

The script will prompt you if it wants to do anything destructive. 

## Packages ##

We want to provide native packages for Flapjack (`.deb`, `.rpm`, `.ebuild`). If 
you'd like to contribute please let us know! 
