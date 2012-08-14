# duplicating some setup stuff to get thin starting properly

FLAPJACK_ENV = ENV['FLAPJACK_ENV'] || 'development'

require 'bundler'

Bundler.require(:default, FLAPJACK_ENV.to_sym)

# add lib to the default include path
unless $:.include?(File.dirname(__FILE__) + '/lib/')
  $: << File.dirname(__FILE__) + '/lib'
end

require 'flapjack/web'
run Flapjack::Web
