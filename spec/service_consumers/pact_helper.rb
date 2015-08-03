require 'pact/provider/rspec'

require 'flapjack'
require 'flapjack/configuration'
require 'flapjack/redis_proxy'

require 'flapjack/gateways/jsonapi'

require './spec/support/mock_logger.rb'

require './spec/service_consumers/fixture_data.rb'
require './spec/service_consumers/provider_support.rb'

require './spec/service_consumers/provider_states_for_flapjack-diner.rb'

FLAPJACK_ENV    = ENV["FLAPJACK_ENV"] || 'test'
FLAPJACK_ROOT   = File.join(File.dirname(__FILE__), '..')
FLAPJACK_CONFIG = File.join(FLAPJACK_ROOT, 'etc', 'flapjack_test_config.toml')
ENV['RACK_ENV'] = ENV["FLAPJACK_ENV"]

require 'bundler'
Bundler.require(:default, :test)

ActiveSupport.use_standard_json_time_format = true
ActiveSupport.time_precision = 0

MockLogger.configure_log('flapjack-jsonapi')
Zermelo.logger = Flapjack.logger = MockLogger.new

# ::RSpec.configuration.full_backtrace = true

Flapjack::Gateways::JSONAPI.class_eval do
  set :show_exceptions, false
  set :raise_errors, false
end

cfg = Flapjack::Configuration.new
$redis_options = cfg.load(FLAPJACK_CONFIG) ?
                 cfg.for_redis :
                 {:db => 14, :driver => :ruby}

Flapjack::RedisProxy.config = $redis_options
Zermelo.redis = Flapjack.redis

Flapjack::Gateways::JSONAPI.instance_variable_set('@config', 'port' => 19081)

Flapjack::Gateways::JSONAPI.start

Pact.configure do |config|
  config.include ::FixtureData
  config.include ::ProviderSupport
end

Pact.service_provider "flapjack" do

  app { Flapjack::Gateways::JSONAPI.new }

  honours_pact_with 'flapjack-diner' do
    pact_uri './spec/service_consumers/pacts/flapjack-diner_v2.0.json'
  end
end