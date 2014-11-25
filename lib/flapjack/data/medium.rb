#!/usr/bin/env ruby

require 'sandstorm/records/redis_record'

require 'flapjack/data/validators/id_validator'

require 'flapjack/data/alert'
require 'flapjack/data/check'

module Flapjack

  module Data

    class Medium

      include Sandstorm::Records::RedisRecord
      include ActiveModel::Serializers::JSON
      self.include_root_in_json = false

      TYPES = ['email', 'sms', 'jabber', 'pagerduty', 'sns', 'sms_twilio']

      define_attributes :type              => :string,
                        :address           => :string,
                        :interval          => :integer,
                        :rollup_threshold  => :integer,
                        :last_rollup_type  => :string,
                        :last_notification => :timestamp,
                        :last_notification_state => :string

      belongs_to :contact, :class_name => 'Flapjack::Data::Contact',
        :inverse_of => :media

      has_and_belongs_to_many :routes, :class_name => 'Flapjack::Data::Route',
        :inverse_of => :media

      has_many :alerts, :class_name => 'Flapjack::Data::Alert', :inverse_of => :medium
      has_and_belongs_to_many :alerting_checks, :class_name => 'Flapjack::Data::Check',
        :inverse_of => :alerting_media

      index_by :type

      validates :type, :presence => true,
        :inclusion => {:in => Flapjack::Data::Medium::TYPES }
      validates :address, :presence => true
      validates :interval, :presence => true,
        :numericality => {:greater_than_or_equal_to => 0, :only_integer => true}
      validates :rollup_threshold, :allow_blank => true,
        :numericality => {:greater_than => 0, :only_integer => true}

      validates_with Flapjack::Data::Validators::IdValidator

      def self.jsonapi_attributes
        [:type, :address, :interval, :rollup_threshold]
      end

      def self.jsonapi_singular_associations
        [:contact]
      end

      def self.jsonapi_multiple_associations
        [:routes]
      end

      def self.as_jsonapi(options = {})
        media = options[:resources]
        return [] if media.nil? || media.empty?

        unwrap = options[:unwrap]

        media_ids = options[:ids]
        contact_ids = Flapjack::Data::Medium.intersect(:id => media_ids).
          associated_ids_for(:contact)
        route_ids = Flapjack::Data::Medium.intersect(:id => media_ids).
          associated_ids_for(:routes)

        data = media.collect do |medium|
          medium.as_json(:only => options[:fields]).merge(:links => {
            :contact => contact_ids[medium.id],
            :routes  => route_ids[medium.id]
          })
        end

        return data unless (data.size == 1) && unwrap
        data.first
      end
    end
  end
end