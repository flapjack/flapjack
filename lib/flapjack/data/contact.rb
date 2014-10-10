#!/usr/bin/env ruby

# NB: use of redis.keys probably indicates we should maintain a data
# structure to avoid the need for this type of query

require 'set'
require 'ice_cube'

require 'sandstorm/records/redis_record'

require 'flapjack/data/medium'
require 'flapjack/data/notification_block'
require 'flapjack/data/rule'
require 'flapjack/data/tag'

require 'securerandom'

module Flapjack

  module Data

    class Contact

      include Sandstorm::Records::RedisRecord
      include ActiveModel::Serializers::JSON
      self.include_root_in_json = false

      define_attributes :name            => :string,
                        :timezone        => :string

      has_and_belongs_to_many :checks, :class_name => 'Flapjack::Data::Check',
        :inverse_of => :contacts

      has_many :media, :class_name => 'Flapjack::Data::Medium'
      has_one :pagerduty_credentials, :class_name => 'Flapjack::Data::PagerdutyCredentials'

      has_many :rules, :class_name => 'Flapjack::Data::Rule'

      before_destroy :remove_child_records
      def remove_child_records
        self.media.each  {|medium| medium.destroy }
        self.rules.each  {|rule|   rule.destroy }
      end

      # return the timezone of the contact, or the system default if none is set
      # TODO cache?
      def time_zone(opts = {})
        tz_string = self.timezone
        tz = opts[:default] if (tz_string.nil? || tz_string.empty?)

        if tz.nil?
          begin
            tz = ActiveSupport::TimeZone.new(tz_string)
          rescue ArgumentError
            if logger
              logger.warn("Invalid timezone string set for contact #{self.id} or TZ (#{tz_string}), using 'UTC'!")
            end
            tz = ActiveSupport::TimeZone.new('UTC')
          end
        end
        tz
      end

      # sets or removes the time zone for the contact
      # nil should delete TODO test
      def time_zone=(tz)
        self.timezone = tz.respond_to?(:name) ? tz.name : tz
      end

      def as_json(opts = {})
        self.attributes.merge(
          :links => {
            :checks                => opts[:check_ids] || [],
            :media                 => opts[:medium_ids] || [],
            :pagerduty_credentials => opts[:pagerduty_credentials_ids] || [],
            :rules                 => opts[:rule_ids] || []
          }
        )
      end

    end
  end
end
