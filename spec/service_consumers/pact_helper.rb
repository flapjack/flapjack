require 'pact/provider/rspec'

require 'flapjack/configuration'
require 'flapjack/gateways/jsonapi'

require './spec/service_consumers/provider_states_for_flapjack-diner.rb'

FLAPJACK_ENV    = ENV["FLAPJACK_ENV"] || 'test'
FLAPJACK_ROOT   = File.join(File.dirname(__FILE__), '..')
FLAPJACK_CONFIG = File.join(FLAPJACK_ROOT, 'etc', 'flapjack_config.yaml')
ENV['RACK_ENV'] = ENV["FLAPJACK_ENV"]

require 'bundler'
Bundler.require(:default, :test)

class MockLogger
  attr_accessor :messages

  def initialize
    @messages = []
  end

  %w(debug info warn error fatal).each do |level|
    class_eval <<-RUBY
      def #{level}?
        true
      end

      def #{level}(msg)
        @messages << msg
      end
    RUBY
  end
end

Flapjack::Gateways::JSONAPI.instance_variable_get('@middleware').delete_if {|m|
  m[0] == Rack::FiberPool
}

Flapjack::Gateways::JSONAPI.class_eval do
  set :show_exceptions, false
  set :raise_errors, false
  error do
    Flapjack::Gateways::JSONAPI.instance_variable_get('@rescue_exception').
      call(env, env['sinatra.error'])
  end
end

cfg = Flapjack::Configuration.new
$redis_options = cfg.load(FLAPJACK_CONFIG) ?
                 cfg.for_redis :
                 {:db => 14, :driver => :ruby}

Flapjack::Gateways::JSONAPI.instance_variable_set('@config', 'port' => 19081)

Flapjack::Gateways::JSONAPI.instance_variable_set('@redis_config', $redis_options)
Flapjack::Gateways::JSONAPI.instance_variable_set('@logger', MockLogger.new)

Flapjack::Gateways::JSONAPI.start

Pact.configure do |config|

end

Pact.service_provider "flapjack" do

  app { Flapjack::Gateways::JSONAPI.new }

  honours_pact_with 'flapjack-diner' do
    pact_uri './spec/service_consumers/pacts/flapjack-diner_v1.0.json'
  end
end