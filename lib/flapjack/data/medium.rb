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

      TRANSPORTS = ['email', 'sms', 'jabber', 'pagerduty', 'sns', 'sms_twilio']

      define_attributes :transport               => :string,
                        :address                 => :string,
                        :interval                => :integer,
                        :rollup_threshold        => :integer,
                        :last_rollup_type        => :string

      belongs_to :contact, :class_name => 'Flapjack::Data::Contact',
        :inverse_of => :media

      has_and_belongs_to_many :rules, :class_name => 'Flapjack::Data::Rule',
        :inverse_of => :media

      has_many :alerts, :class_name => 'Flapjack::Data::Alert', :inverse_of => :medium
      has_and_belongs_to_many :alerting_checks, :class_name => 'Flapjack::Data::Check',
        :inverse_of => :alerting_media

      belongs_to :last_entry, :class_name => 'Flapjack::Data::Entry',
        :inverse_of => :latest_media, :before_remove => :debug_remove

      def debug_remove(e)
        trace = caller[0..5].join("\n")
        Flapjack.logger.info "medium #{self.id} removing entry #{e.id}:\n#{trace}"
      end

      index_by :transport

      validates :transport, :presence => true,
        :inclusion => {:in => Flapjack::Data::Medium::TRANSPORTS }

      validates :address, :presence => true

      validates :interval, :presence => true,
        :numericality => {:greater_than_or_equal_to => 0, :only_integer => true},
        :unless => proc {|m| 'pagerduty'.eql?(m.transport) }

      validates :rollup_threshold, :allow_nil => true,
        :numericality => {:greater_than => 0, :only_integer => true},
        :unless => proc {|m| 'pagerduty'.eql?(m.transport) }

      validates_each :interval, :rollup_threshold,
        :if =>  proc {|m| 'pagerduty'.eql?(m.transport) } do |record, att, value|

        record.errors.add(att, 'must be nil') unless value.nil?
      end

      validates_with Flapjack::Data::Validators::IdValidator

      def self.jsonapi_attributes
        [:transport, :address, :interval, :rollup_threshold]
      end

      def self.jsonapi_singular_associations
        [:contact]
      end

      def self.jsonapi_multiple_associations
        [:rules]
      end
    end
  end
end