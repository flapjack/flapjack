#!/usr/bin/env ruby 

# Nothing Flapjack-specific here - feel free to reuse.

module Flapjack
  class Inifile
  
    def initialize(string)
      @data = {}
  
      string.split("\n").each do |line|
        if line =~ /^\s*\[(.+)\]\s*(;.+)*$/
          @current_section = $1
          @data[@current_section] ||= {}
        end
        if line =~ /^\s*(.+)\s*=\s*([^;]+)\s*(;.+)*$/ # after = captures up to ; then groups everything after ;
          key = $1.strip
          value = $2.strip
          @data[@current_section][key] = value
        end
      end
    end
  
    def [](key)
      @data[key]
    end
  
    def keys
      @data.keys
    end
  
    def self.read(filename)
      self.new(File.read(filename))
    end
  
  end
end

