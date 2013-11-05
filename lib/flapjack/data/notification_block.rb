#!/usr/bin/env ruby

require 'sandstorm/record'

require 'flapjack/data/check_state'

module Flapjack
  module Data
    class NotificationBlock

      include Sandstorm::Record

      define_attributes :expire_at        => :timestamp,
                        :rollup           => :boolean,
                        :state            => :string      # may be nil

      index_by :state, :rollup

      belongs_to :check, :class_name => 'Flapjack::Data::Check', :inverse_of => :notification_blocks
      belongs_to :medium, :class_name => 'Flapjack::Data::Medium', :inverse_of => :notification_blocks

      # TODO if rollup == true, media_type must be set, entity_check_id and state not set
      #      if rollup == false, media_type, entity_check_id and state must be set

      # can't handle these via validations as associations require an already saved record

      validate :expire_at, :presence => true
      validate :state,
        :inclusion => { :in => Flapjack::Data::CheckState.all_states, :allow_blank => true }

    end
  end
end
