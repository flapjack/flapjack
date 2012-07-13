#!/usr/bin/env ruby

$: << File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'lib'))

require 'pathname'
require 'yajl'
require 'beanstalk-client'
require 'daemons'
require 'flapjack/notifier'
require 'flapjack/patches'


Before('@events') do
  app = Flapjack::Notifier.run
  app.process_events
  @redis = Redis.new
end

After('@events') do

end

