FROM ubuntu:12.04

RUN echo deb http://packages.flapjack.io/deb/1.0 precise main >> /etc/apt/sources.list
RUN apt-get update
RUN apt-get install -y --force-yes flapjack

#CMD /etc/init.d/redis-flapjack start && /opt/flapjack/bin/flapjack start --no-daemonize

