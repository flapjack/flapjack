#!/usr/bin/env ruby

require 'sandstorm/record'

require 'flapjack/data/contact'
require 'flapjack/data/check'

module Flapjack

  module Data

    class Entity

      include Sandstorm::Record

      include ActiveModel::Serializers::JSON
      self.include_root_in_json = false

      define_attributes :name    => :string,
                        :enabled => :boolean,
                        :tags    => :set

      unique_index_by :name
      index_by :enabled

      has_and_belongs_to_many :contacts, :class_name => 'Flapjack::Data::Contact',
        :inverse_of => :entities

      has_many :checks, :class_name => 'Flapjack::Data::Check'

      validate :name, :presence => true

      # NB: if we're worried about user input, https://github.com/mudge/re2
      # has bindings for a non-backtracking RE engine that runs in linear
      # time
      # Raises RegexpError if the provided pattern is invalid
      def self.find_all_name_matching(pattern)
        regexp = Regexp.new(pattern)
        Flapjack.redis.hkeys(self.name_index(nil).key).select {|name|
          name =~ regexp
        }.sort
      end

      def self.find_by_set_intersection(key, *values)
        return if values.blank?

        load_from_key = proc {|k|
          k =~ /\A#{class_key}:([^:]+):attrs:#{key.to_s}\z/
          find_by_id($1)
        }
        temp_set = "#{class_key}::tmp:#{SecureRandom.hex(16)}"
        Flapjack.redis.sadd(temp_set, values)

        keys = Flapjack.redis.keys("#{class_key}:*:attrs:#{key}")

        result = keys.inject([]) do |memo, k|
          if Flapjack.redis.sdiff(temp_set, k).empty?
            memo << load_from_key.call(k)
          end
          memo
        end

        Flapjack.redis.del(temp_set)
        result
      end

    end

  end

end
