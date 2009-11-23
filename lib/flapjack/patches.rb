require 'ostruct'
require 'daemons'
require 'log4r'

class OpenStruct
  def to_h
    @table
  end
end

module Daemons
  class PidFile 
    # we override this method so creating pid files is fork-safe
    def filename 
      File.join(@dir, "#{@progname}#{Process.pid}.pid")
    end
  end
end

module Log4r
  class Logger
    def error(args)
      err(args)
    end

    def warning(args)
      warn(args)
    end
  end
end
