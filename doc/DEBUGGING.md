Here's some useful ways of debugging various things in Flapjack.

Redis Connection Leaks

The following command reports every five seconds the number of connections to redis (as reported by lsof) and the totall number of EM external protocol connections currently in place:

    while true ; do echo -n "EM connection count: " ; tail -50000 /var/log/flapjack/flapjack.log | grep -i "connection count" | tail -1 | awk '{ print $5 }' ; echo -n "lsof redis: " ; sudo lsof -p `cat /var/run/flapjack/flapjack.pid` | grep :6379 | wc -l ; sleep 5 ; done

