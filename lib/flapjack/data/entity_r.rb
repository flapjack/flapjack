#!/usr/bin/env ruby

require 'flapjack/data/contact_r'
require 'flapjack/data/entity_check_r'

module Flapjack

  module Data

    class EntityR

      include Flapjack::Data::RedisRecord

      define_attributes :name    => :string,
                        :enabled => :boolean,
                        :tags    => :set

      index_by :name, :enabled

      has_many :contacts, :class_name => 'Flapjack::Data::ContactR'

      # NB replaces check_list, check_count
      has_many :checks, :class_name => 'Flapjack::Data::EntityCheckR'

      validate :name, :presence => true

      after_destroy :remove_contact_linkages
      def remove_contact_linkages
        contacts.each do |contact|
          contact.entities.delete(self)
        end
      end

      # NB: if we're worried about user input, https://github.com/mudge/re2
      # has bindings for a non-backtracking RE engine that runs in linear
      # time
      # Raises RegexpError if the provided pattern is invalid
      def self.find_all_names_matching(pattern)
        regexp = Regexp.new(pattern)
        prefix = "#{class_key}::by_name"
        Flapjack.redis.keys("#{prefix}:*").inject(Set.new) {|memo, key|
          name = key.gsub(/\A#{prefix}:/, '')
          memo << name if (name =~ regex)
          memo
        }.sort
      end

      # TODO change uses of Entity.all to EntityR.all.sort_by(&:name)

      # TODO change uses of Entity.find_by_name(N) to EntityR.find_by(:name, N)
    end

  end

end
