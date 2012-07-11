#!/usr/bin/env ruby

$: << File.dirname(__FILE__) + '/../lib' unless $:.include?(File.dirname(__FILE__) + '/../lib/')

require 'flapjack/notifier'
require 'flapjack/patches'

app = Flapjack::Notifier.new
app.process_events
