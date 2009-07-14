require 'ostruct'
require 'daemons'

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

class Log4r::Logger
  def error(args)
    err(args)
  end
end
