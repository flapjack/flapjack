desc 'Receive events from external systems and send them to Flapjack'
arg_name 'receiver'
command :receiver do |receiver|

  receiver.desc 'Nagios receiver'
  #receiver.arg_name 'Turn Nagios check results into Flapjack events'
  receiver.command :nagios do |nagios|
    nagios.action do |global_options,options,args|
      puts "nagios command ran"
    end
  end

  receiver.desc 'NSCA receiver'
  #receiver.arg_name 'Turn Nagios passive check results into Flapjack events'
  receiver.command :nsca do |nsca|
    nsca.action do |global_options,options,args|
      puts "nsca command ran"
    end
  end

  receiver.desc 'JSON receiver'
  receiver.command :json do |json|
    json.action do |global_options,options,args|
      puts "json command ran"
    end
  end

  receiver.desc 'Mirror receiver'
  receiver.command :mirror do |mirror|
    mirror.action do |global_options,options,args|
      puts "mirror command ran"
    end
  end

end

