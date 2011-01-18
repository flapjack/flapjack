#!/usr/bin/env ruby

$: << File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'lib'))

require 'pathname'
require 'yajl'
require 'beanstalk-client'

class ProcessManagement
  # Cleans up daemons that were started in a scenario.
  # We kill these daemons so the test state is clean at the beginning of every
  # scenario, and scenarios don't become coupled with one another.
  def kill_lingering_daemons
    @daemons.each do |pipe|
      Process.kill("KILL", pipe.pid)
    end
  end

  # Testing daemons with Ruby backticks blocks indefinitely, because the
  # backtick method waits for the program to exit. We use the select() system
  # call to read from a pipe connected to a daemon, and return if no data is
  # read within the specified timeout.
  #
  # http://weblog.jamisbuck.org/assets/2006/9/25/gdb.rb
  def read_until_timeout(pipe, timeout=1, verbose=false)
    output = []
    line    = ""
    while data = IO.select([pipe], nil, nil, timeout) do
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

  def spawn_daemon(command)
    @daemons ||= []
    daemon = IO.popen(command)
    @daemons << daemon
    daemon
  end

end

After do |scenario|
  kill_lingering_daemons
end

World do
  ProcessManagement.new
end
