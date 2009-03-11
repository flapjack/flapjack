#!/usr/bin/env ruby

require 'bin/common'
require 'beanstalk-client'
require 'ostruct'
require 'optparse'
require 'log4r'
require 'log4r/outputter/syslogoutputter'
require 'lib/flapjack/result'
require 'lib/flapjack/notifier'
require 'lib/flapjack/notifiers/mailer'
require 'lib/flapjack/notifiers/xmpp'

include Log4r

class Options
  def self.parse(args)
    options = OpenStruct.new
    opts = OptionParser.new do |opts|
      # the available command line options
      opts.on('-b', '--beanstalk HOST', 'location of the beanstalkd') do |host|
        options.host = host
      end
      opts.on_tail("-h", "--help", "Show this message") do
        puts opts
        exit
      end
    end

    # parse the options
    begin
      opts.parse!(args)
    rescue OptionParser::MissingArgument => e
      # if an --option is missing it's argument
      puts e.message.capitalize + "\n\n"
      puts opts
      exit 1
    end

    # check that the host is specified
    unless options.host 
      puts opts
      exit 2
    end

    options
  end
end


# if we're run as a script
if __FILE__ == $0 then
  
  log = Log4r::Logger.new("notifier")
  log.add(Log4r::StdoutOutputter.new('notifier'))
  log.add(Log4r::SyslogOutputter.new('notifier'))
  
  mailer = Mailer.new
  xmpp = Xmpp.new(:jid => "flapjack-test@jabber.org", :password => "test")

  @notifier = Notifier.new(:logger => log, :notifiers => [mailer, xmpp])
  @options = Options.parse(ARGV)

  begin 
    @results = Beanstalk::Pool.new(["#{@options.host}:11300"], 'results')
    log.info("established connection to beanstalkd on #{@options.host}...")

    loop do
      result = @results.reserve
      r = Result.new(YAML::load(result.body))
      if r.warning? || r.critical?
        @notifier.notify!(r)
      end
      result.delete
    end
  rescue Beanstalk::NotConnected
    log.error("beanstalk isn't up!")
    exit 2
  end

end
