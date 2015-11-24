#!/usr/bin/env ruby

require 'active_support/time'
require 'active_support/json/encoding'

ActiveSupport.use_standard_json_time_format = true
ActiveSupport.time_precision = 0

require 'json'

require 'flapjack/logger'

module Flapjack
  UUID_RE = "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"

  DEFAULT_INITIAL_FAILURE_DELAY = 30
  DEFAULT_REPEAT_FAILURE_DELAY  = 60

  # defaulting to 0 for backwards compatibility; can be overridden in config,
  # or per check / event
  DEFAULT_INITIAL_RECOVERY_DELAY = 0

  def self.load_json(data)
    ActiveSupport::JSON.decode(data)
  end

  def self.dump_json(data)
    ActiveSupport::JSON.encode(data)
  end

  def self.sanitize(str)
    return str if str.nil? || !str.is_a?(String) || str.valid_encoding?
    return str.scrub('?') if str.respond_to(:scrub)
    str.chars.collect {|c| c.valid_encoding? ? c : '_' }.join
  end
end
