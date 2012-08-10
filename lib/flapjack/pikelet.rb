# Encapsulates the config loading and environment setup used
# by the various Flapjack components
module Flapjack
  module Pikelet
    
    def included(mod)
      class << mod
        attr_accessor :bootstrapped, :persistence, :logger, :config
      end
    end
    
    # FIXME: this should register the running pikelet as a unique instance in redis
    # perhaps look at resque's code, how it does this
    def instance
      1
    end

    def bootstrapped?
      !!@bootstrapped
    end
    
    def bootstrap(options = {})
      return if bootstrapped?
      
      defaults = {
        :redis => {
          :db => 0
        }
      }
      options = defaults.merge(opts)

      @persistence = ::Redis.new(options[:redis])

      unless @log = options[:logger]
        @log = Log4r::Logger.new("flapjack")
        @log.add(Log4r::StdoutOutputter.new("flapjack"))
        @log.add(Log4r::SyslogOutputter.new("flapjack"))
      end

      @config  = options[:config] || {}

      @bootstrapped = true
    end
      
  end
end