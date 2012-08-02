#!/usr/bin/env ruby

$: << File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'lib'))

require 'pathname'
require 'yajl'
require 'beanstalk-client'
require 'daemons'
require 'flapjack/executive'
require 'flapjack/patches'


Before('@events') do
  # Use a separate database whilst testing
  @app = Flapjack::Executive.new(:redis => { :db => 14 })
  @app.drain_events
  @redis = Flapjack.persistence
end

After('@events') do

end

