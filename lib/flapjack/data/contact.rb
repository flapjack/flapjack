#!/usr/bin/env ruby

# NB: use of redis.keys probably indicates we should maintain a data
# structure to avoid the need for this type of query

require 'set'
require 'ice_cube'

require 'sandstorm/records/redis_record'

require 'flapjack/data/validators/id_validator'

require 'flapjack/data/medium'
require 'flapjack/data/rule'
require 'flapjack/data/tag'

require 'securerandom'

module Flapjack

  module Data

    class Contact

      include Sandstorm::Records::RedisRecord
      include ActiveModel::Serializers::JSON
      self.include_root_in_json = false

      define_attributes :name                     => :string,
                        :timezone                 => :string

      has_and_belongs_to_many :checks, :class_name => 'Flapjack::Data::Check',
        :inverse_of => :contacts

      has_many :media, :class_name => 'Flapjack::Data::Medium', :inverse_of => :contact
      has_one :pagerduty_credentials, :class_name => 'Flapjack::Data::PagerdutyCredentials',
        :inverse_of => :contact

      has_many :rules, :class_name => 'Flapjack::Data::Rule', :inverse_of => :contact

      validates_with Flapjack::Data::Validators::IdValidator

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

      def self.as_jsonapi(unwrap, *contacts)
        return [] if contacts.empty?
        contact_ids = contacts.map(&:id)

        # medium_ids = Flapjack::Data::Contact.intersect(:id => contact_ids).
        #   associated_ids_for(:media)
        # pagerduty_credentials_ids = Flapjack::Data::Contact.
        #   intersect(:id => contact_ids).associated_ids_for(:pagerduty_credentials)
        # rule_ids = Flapjack::Data::Contact.intersect(:id => contact_ids).
        #   associated_ids_for(:rules)

        data = contacts.collect do |contact|
          contact.as_json

          # :links => {
          #   :media                 => opts[:medium_ids] || [],
          #   :pagerduty_credentials => opts[:pagerduty_credentials_ids] || [],
          #   :rules                 => opts[:rule_ids] || []
          # }

          # (
          #   :medium_ids => medium_ids[contact.id],
          #   :pagerduty_credentials_ids => pagerduty_credentials_ids[contact.id],
          #   :rule_ids => rule_ids[contact.id]
          # )
        end
        return data unless (data.size == 1) && unwrap
        data.first
      end

    end
  end
end
