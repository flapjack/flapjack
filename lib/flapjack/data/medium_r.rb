#!/usr/bin/env ruby

# require 'flapjack/data/entity_check_r'

module Flapjack

  module Data

    class MediumR

      include Flapjack::Data::RedisRecord

      define_attributes :type => :string,
                        :address  => :string,
                        :interval => :integer

      belongs_to :contact, :class_name => 'Flapjack::Data::ContactR'

      index_by :type

      # ??
      # has_many :checks, :class_name => 'Flapjack::Data::EntityCheckR'

      validates :type, :presence => true
      validates :address, :presence => true
      validates :interval, :presence => true,
        :numericality => {:greater_than => 0, :only_integer => true}

      # # replaces the following methods from contact.rb
      # def interval_for_media(media)
      # def set_interval_for_media(media, interval)
      # def set_address_for_media(media, address)
      # def remove_media(media)

      # contact.media_list should be replaced by
      # contact.media.collect {|m| m['address'] }

    end

  end

end