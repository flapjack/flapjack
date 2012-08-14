# duplicating some setup stuff to get thin starting properly

unless defined?(FLAPJACK_ENV)
  FLAPJACK_ENV = ENV['FLAPJACK_ENV'] || 'development'
end

require 'bundler'

Bundler.require(:default, FLAPJACK_ENV.to_sym)

# add lib to the default include path
unless $:.include?(File.dirname(__FILE__) + '/lib/')
  $: << File.dirname(__FILE__) + '/lib'
end

require 'flapjack/web'
run Flapjack::Web
