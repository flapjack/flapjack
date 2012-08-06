#!/usr/bin/env ruby

module Flapjack
  def self.bootstrap(opts={})
    if not bootstrapped?
      defaults = {
        :redis => {
          :db => 0
        }
      }
      @options = defaults.merge(opts)

      @@persistence = ::Redis.new(@options[:redis])

      if not @@logger = @options[:logger]
        @@logger = Log4r::Logger.new("flapjack")
        @@logger.add(Log4r::StdoutOutputter.new("flapjack"))
        @@logger.add(Log4r::SyslogOutputter.new("flapjack"))
      end

      @@apphome = File.absolute_path(File.dirname(__FILE__) + '/../')
      @@config  = YAML.load_file(@@apphome + '/etc/flapjack_config.yaml')
    end

    @bootstrapped = true
  end

  def self.bootstrapped?
    @bootstrapped
  end

  def self.persistence
    @@persistence
  end

  def self.logger
    @@logger
  end

  # FIXME: this should register the running flapjack as a unique instance in redis
  # perhaps look at resque's code, how it does this
  def self.instance
    1
  end

  def self.config
    #@@apphome ||= File.absolute_path(File.dirname(__FILE__) + '/../')
    #@@config  ||= YAML.load(@@apphome + '/etc/flapjack_config.yaml')
    @@logger.debug @@config.inspect
    @@config
  end

end

