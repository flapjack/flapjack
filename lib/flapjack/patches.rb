#!/usr/bin/env ruby

require 'logger'

# bugfix for webrick's assuming 1.8.7 Logger syntax
class ::Logger; alias_method :write, :<<; end
