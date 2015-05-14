#!/usr/bin/env ruby

# the name represents a 'log entry', as Flapjack's data model resembles an
# audit log.

# TODO when removed from an associated check or notification, if the rest of
# those associations are not present, remove it from the state's associations
# and delete it

require 'flapjack/data/notification'
require 'flapjack/data/state'

module Flapjack
  module Data
    class Entry

      include Zermelo::Records::Redis

      define_attributes :timestamp     => :timestamp,
                        :condition     => :string,
                        :action        => :string,
                        :summary       => :string,
                        :details       => :string,
                        :perfdata_json => :string

      index_by :condition, :action
      range_index_by :timestamp

      belongs_to :last_notifications_check, :class_name => 'Flapjack::Data::Check',
        :inverse_of => :last_notification

      belongs_to :state, :class_name => 'Flapjack::Data::State',
        :inverse_of => :entries

      has_one :notification, :class_name => 'Flapjack::Data::Notification',
        :inverse_of => :entry

      has_many :latest_media, :class_name => 'Flapjack::Data::Medium',
        :inverse_of => :last_entry

      validates :timestamp, :presence => true

      validates :condition, :allow_blank => true,
        :inclusion => { :in => Flapjack::Data::Condition.healthy.keys +
                               Flapjack::Data::Condition.unhealthy.keys }

      ACTIONS = %w(acknowledgement test_notifications)
      validates :action, :allow_nil => true,
        :inclusion => {:in => Flapjack::Data::Entry::ACTIONS}

      # TODO handle JSON exception
      def perfdata
        if self.perfdata_json.nil?
          @perfdata = nil
          return
        end
        @perfdata ||= Flapjack.load_json(self.perfdata_json)
      end

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

      def self.delete_if_unlinked(e)
        Flapjack.logger.debug "checking deletion of #{e.instance_variable_get('@attributes').inspect}"
        Flapjack.logger.debug "state nil #{e.state.nil?}"
        Flapjack.logger.debug "last_notification_check nil #{e.last_notification_check.nil?}"
        Flapjack.logger.debug "notification nil #{e.notification.nil?}"
        Flapjack.logger.debug "latest media empty #{e.latest_media.empty?}"

        return unless e.state.nil? && e.last_notification_check.nil? &&
          e.notification.nil? && e.latest_media.empty?
        Flapjack.logger.debug "deleting"
        e.destroy
      end
    end
  end
end

