#!/usr/bin/env ruby

require 'sandstorm/records/redis_record'

require 'flapjack/data/contact'
require 'flapjack/data/check'

module Flapjack

  module Data

    class Entity

      # TODO how to integrate contacts_for:ALL ?

      include Sandstorm::Records::RedisRecord

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

      # TODO validate uniqueness of name

      validate :name, :presence => true

      def as_json(opts = {})
        super.as_json(opts).merge(
          :links => {
            :contacts => opts[:contact_ids] || [],
            :checks   => opts[:checks_ids] || []
          }
        )
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
