#!/usr/bin/env ruby

require 'active_support/json/encoding'

ActiveSupport::JSON::Encoding.use_standard_json_time_format = true
ActiveSupport::JSON::Encoding.time_precision = 0

require 'active_support/time'
require 'oj'

require 'flapjack/logger'

module Flapjack

  UUID_RE = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"

  DEFAULT_INITIAL_FAILURE_DELAY = 30
  DEFAULT_REPEAT_FAILURE_DELAY  = 60

  # https://github.com/flapjack/flapjack/issues/449 , not done yet but
  # designing around this for now
  SEPARATE_STATE_HISTORY = false

  def self.load_json(data)
    Oj.load(data, :mode => :strict, :symbol_keys => false)
  end

  def self.dump_json(data)
    Oj.dump(data, :mode => :compat, :time_format => :ruby, :indent => 0)
  end

end
