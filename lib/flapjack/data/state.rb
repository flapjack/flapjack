#!/usr/bin/env ruby

require 'sandstorm/records/redis_record'

require 'flapjack/data/validators/id_validator'

module Flapjack
  module Data
    class State

      include Sandstorm::Records::RedisRecord
      include ActiveModel::Serializers::JSON
      self.include_root_in_json = false

      define_attributes :timestamp     => :timestamp,
                        :condition     => :string,
                        :condition_changed => :boolean,
                        :action        => :string,
                        :notified      => :boolean,
                        :summary       => :string,
                        :details       => :string,
                        :perfdata_json => :string,
                        :count         => :integer,
                        :last_notification_count => :integer # ???

      unique_index_by :count
      index_by :condition, :condition_changed, :action, :notified

      belongs_to :check, :class_name => 'Flapjack::Data::Check', :inverse_of => :states

      has_many :notifications, :class_name => 'Flapjack::Data::Notification',
        :inverse_of => :state

      has_many :media, :class_name => 'Flapjack::Data::Medium',
        :inverse_of => :last_notification_state

      validates_with Flapjack::Data::Validators::IdValidator

      validates :timestamp, :presence => true

      validates :condition, :presence => true,
        :inclusion => {:in => Flapjack::Data::Condition::HEALTHY.values +
                              Flapjack::Data::Condition::UNHEALTHY.values}

      ACTIONS = %w(acknowledgement test_notifications)

      validates :action, :allow_nil => true, :inclusion => {:in => ACTIONS}

      validates :notified, :presence => true, :inclusion => {:in => [true, false]}

      # example perfdata: time=0.486630s;;;0.000000 size=909B;;;0
      def perfdata=(data)
        if data.nil?
          self.perfdata_json = nil
          return
        end

        data = data.strip
        if data.length == 0
          self.perfdata_json = nil
          return
        end
        # Could maybe be replaced by a fancy regex
        @perfdata = data.split(' ').inject([]) do |item|
          parts = item.split('=')
          memo << {"key"   => parts[0].to_s,
                   "value" => parts[1].nil? ? '' : parts[1].split(';')[0].to_s}
          memo
        end
        self.perfdata_json = @perfdata.nil? ? nil : Flapjack.dump_json(@perfdata)
      end

      def self.jsonapi_attributes
        []
      end

      def self.jsonapi_singular_associations
        []
      end

      def self.jsonapi_multiple_associations
        []
      end

    end
  end
end