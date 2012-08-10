#!/usr/bin/env ruby

require 'rubygems'
require 'bundler'
Bundler.require(:default, :web)

$: << File.expand_path(File.join(File.dirname(__FILE__), 'lib'))
require 'flapjack/web'

use Flapjack::Web
run Sinatra::Application
