#!/usr/bin/env ruby

require 'sandstorm/record'

require 'flapjack/data/check_state'

module Flapjack
  module Data
    class NotificationBlock

      include Sandstorm::Record

      # TODO make notification logic smarter about checking these -- belong_to
      # medium and entity check

      # TODO with rollup == true, replaces drop_rollup_alerts_for_contact
      # existing NotificationBlock usage will need to be have 'rollup == false' added

      define_attributes :expire_at        => :timestamp,
                        :rollup           => :boolean,
                        :media_type       => :string,     # may be nil
                        :entity_check_id  => :id,         # may be nil
                        :state            => :string      # may be nil

      index_by :media_type, :entity_check_id, :state

      belongs_to :contact, :class_name => 'Flapjack::Data::Contact'

      # TODO validations -- if rollup == true, media_type must be set, entity_check_id and state not set
      #                     if rollup == false, media_type, entity_check_id and string must be set

      validate :expire_at, :presence => true
      validate :state,
        :inclusion => { :in => Flapjack::Data::CheckState.all_states, :allow_blank => true }

    end
  end
end
