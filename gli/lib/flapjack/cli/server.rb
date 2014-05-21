desc 'Server for running components (e.g. processor, notifier, gateways)'
command :server do |server|

  server.desc 'Start the server'
  server.command :start do |start|
    start.action do |global_options,options,args|
      puts "start command ran"
    end
  end

  server.desc 'Stop the server'
  server.command :stop do |stop|
    stop.action do |global_options,options,args|
      puts "stop command ran"
    end
  end

  server.desc 'Restart the server'
  server.command :restart do |restart|
    restart.action do |global_options,options,args|
      puts "restart command ran"
    end
  end

  server.desc 'Reload the server'
  server.command :reload do |reload|
    reload.action do |global_options,options,args|
      puts "reload command ran"
    end
  end
end
