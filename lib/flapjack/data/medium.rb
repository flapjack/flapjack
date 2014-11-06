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

      def as_json(opts = {})
        aj_opts = opts.merge(
          :root   => false,
          :except => [:last_rollup_type, :last_notification]
        )
        super.as_json(aj_opts).merge(
          :links => {
            :contacts   => opts[:contact_ids] || [],
            :routes     => opts[:route_ids]   || []
          }
        )
      end

    end

  end

end