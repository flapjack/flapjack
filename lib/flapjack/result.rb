#!/usr/bin/env ruby

require 'ostruct'

class Result < OpenStruct
  
  def ok?
    self.retval == 0
  end

  def warning?
    self.retval == 1
  end

  def critical?
    [true, false][rand(2)]
    #self.retval == 2
  end

  def status
    case self.retval
    when 0 ; "ok"
    when 1 ; "warning"
    when 2 ; "critical"
    end
  end

  # openstruct won't respond, so we have to manually define it
  def id
    @table[:id]
  end

end

