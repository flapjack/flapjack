#!/usr/bin/env ruby

require 'gli'
require 'flapjack'
require 'flapjack/version'

include GLI::App

program_desc 'Flexible monitoring notification routing system'

version Flapjack::VERSION

desc 'Configuration file to use'
default_value '/etc/flapjack/flapjack.yaml'
arg_name '/path/to/flapjack.yaml'
flag [:c,:config]

desc 'Environment to boot'
default_value 'production'
arg_name '<environment>'
flag [:n,:env,:environment]

desc 'Artificial service that oscillates up and down'
command :flapper do |c|
  c.action do |global_options,options,args|

    # Your command logic here
    #
    # If you have any errors, just raise them
    # raise "that command made no sense"

    puts "flapper command ran"
  end
end

desc 'Bulk import data from an external source'
command :import do |c|
  c.desc 'import contacts'
  c.command :contacts do |sc|
    sc.action do |global_options,options,args|
      #...
    end
  end
  c.desc 'import entities'
  c.command :entities do |sc|
    sc.action do |global_options,options,args|
      #...
    end
  end
end

desc 'Receive events from external systems and send them to Flapjack'
command :receiver do |c|
  c.desc 'JSON receiver'
  c.command :json do |sc|
    sc.action do |global_options,options,args|
      #...
    end
  end

  c.desc 'Mirror receiver'
  c.command :mirror do |sc|
    sc.action do |global_options,options,args|
      #...
    end
  end

  c.desc 'Nagios receiver'
  c.command :nagios do |sc|
    sc.action do |global_options,options,args|
      #...
    end
  end

  c.desc 'NSCA receiver'
  c.command :nsca do |sc|
    sc.action do |global_options,options,args|
      #...
    end
  end
end

desc 'Server for running components (e.g. processor, notifier, gateways)'
command :server do |c|
  c.desc 'Reload the server'
  c.command :reload do |sc|
    sc.action do |global_options,options,args|
      #...
    end
  end

  c.desc 'Restart the server'
  c.command :restart do |sc|
    sc.action do |global_options,options,args|
      #...
    end
  end

  c.desc 'Start the server'
  c.command :start do |sc|
    sc.action do |global_options,options,args|
      #...
    end
  end

  c.desc 'Stop the server'
  c.command :stop do |sc|
    sc.action do |global_options,options,args|
      #...
    end
  end

  #   c.desc 'server status'
  #   c.command :status do |sc|
  #     sc.action do |global_options,options,args|
  #         #...
  #     end
  #   end

end

desc 'Generate streams of events in various states'
arg_name 'Describe arguments to simulate here'
command :simulate do |c|
  c.desc 'Generate a stream of failure events'
  c.command :fail do |sc|
    sc.action do |global_options,options,args|
      #...
    end
  end

  c.desc 'Generate a stream of failure events, and one final recovery'
  c.command :fail_and_recover do |sc|
    sc.action do |global_options,options,args|
      #...
    end
  end

  c.desc 'Generate a stream of ok events'
  c.command :ok do |sc|
    sc.action do |global_options,options,args|
      #...
    end
  end
end

pre do |global,command,options,args|
  # Pre logic here
  # Return true to proceed; false to abort and not call the
  # chosen command
  # Use skips_pre before a command to skip this block
  # on that command only
  true
end

post do |global,command,options,args|
  # Post logic here
  # Use skips_post before a command to skip this
  # block on that command only
end

on_error do |exception|
  # Error logic here
  # return false to skip default error handling
  true
end

exit run(ARGV)
