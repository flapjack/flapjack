#!/usr/bin/env ruby

require 'active_support/json/encoding'

ActiveSupport::JSON::Encoding.use_standard_json_time_format = true
ActiveSupport::JSON::Encoding.time_precision = 0

require 'active_support/time'
require 'json'

require 'flapjack/logger'

module Flapjack

  UUID_RE = "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"

  DEFAULT_INITIAL_FAILURE_DELAY = 30
  DEFAULT_REPEAT_FAILURE_DELAY  = 60

  def self.load_json(data)
    JSON.parse(data)
  end

  def self.dump_json(data)
    JSON.generate(data)
  end

  def self.sanitize(str)
    return str if str.nil? || !str.is_a?(String) || str.valid_encoding?
    return str.scrub('?') if str.respond_to(:scrub)
    str.chars.collect {|c| c.valid_encoding? ? c : '_' }.join
  end

end
