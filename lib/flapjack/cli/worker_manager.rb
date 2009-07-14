#!/usr/bin/env ruby

require 'rubygems'
require 'ostruct'
require 'optparse' 

class WorkerManagerOptions
  def self.parse(args)
    options = OpenStruct.new
    opts = OptionParser.new do |opts|
      opts.banner = "Usage: flapjack-worker-manager <command> [options]"
      opts.separator " "
      opts.separator "  where <command> is one of:"
      opts.separator "     start            start a worker"
      opts.separator "     stop             stop all workers"
      opts.separator "     restart          restart workers"
      opts.separator " "
      opts.separator "  and [options] are:"

      opts.on('-w', '--workers N', 'number of workers to spin up') do |workers|
        options.workers = workers.to_i
      end
      opts.on('-c', '--checks-directory DIR', 'sandboxed check directory') do |dir|
        options.check_directory = dir
      end
    end

    begin
      opts.parse!(args)
    rescue => e
      puts e.message.capitalize + "\n\n"
      puts opts
      exit 1
    end

    options.workers ||= 5

    unless %w(start stop restart).include?(args[0])
      puts opts
      exit 1
    end

    options
  end
end


