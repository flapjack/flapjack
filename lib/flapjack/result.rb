#!/usr/bin/env ruby

require 'ostruct'

##
# Representation of a check result, as it's popped off the beanstalk.
# 
# Provides several convience methods for querying the status of a result. 
#
# Convenience methods are used by the Notifier to determine whether a 
# notification needs to be sent out.
class Result < OpenStruct

  # Whether a check returns an ok status. 
  def ok?
    self.retval == 0
  end

  # Whether a check has a warning status.
  def warning?
    self.retval == 1
  end

  # Whether a check has a critical status.
  def critical?
    self.retval == 2
  end

  # Human readable representation of the check's return value.
  def status
    case self.retval
    when 0 ; "ok"
    when 1 ; "warning"
    when 2 ; "critical"
    end
  end

  # The id of a check result.
  def id
    # openstruct won't respond, so we have to manually define it
    @table[:id]
  end

end

