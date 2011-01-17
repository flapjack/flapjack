#!/usr/bin/env ruby

$: << File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'lib'))

require 'pathname'
require 'yajl'
require 'beanstalk-client'

class ProcessManagement
  def kill_lingering_daemons
    Process.kill("KILL", @beanstalk.pid) if @beanstalkd
  end

  # http://weblog.jamisbuck.org/assets/2006/9/25/gdb.rb
  def read_until_done(pipe, verbose=false)
    output = []
    line    = ""
    while data = IO.select([pipe], nil, nil, 1) do
      next if data.empty?
      char = pipe.read(1)
      break if char.nil?

      line << char
      if line[-1] == ?\n
        puts line if verbose
        output << line
        line = ""
      end
    end

    output
  end

end

After do |scenario|
  kill_lingering_daemons
end

World do
  ProcessManagement.new
end
