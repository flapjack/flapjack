#!/usr/bin/env ruby

require 'sandstorm/record'

require 'flapjack/data/contact_r'
require 'flapjack/data/entity_check_r'

module Flapjack

  module Data

    class EntityR

      include Sandstorm::Record

      include ActiveModel::Serializers::JSON
      self.include_root_in_json = false

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
      def self.find_all_name_matching(pattern)
        regexp = Regexp.new(pattern)
        prefix = "#{class_key}::by_name"
        Flapjack.redis.keys("#{prefix}:*").inject(Set.new) {|memo, key|
          name = key.gsub(/\A#{prefix}:/, '')
          memo << name if (name =~ regex)
          memo
        }.sort
      end

      def self.find_by_set_intersection(key, *values)
        return if values.blank?

        load_from_key = proc {|k|
          k =~ /\A#{class_key}:([^:]+):attrs:#{key.to_s}\z/
          find_by_id($1)
        }
        temp_set = "#{class_key}::tmp:#{SecureRandom.hex(16)}"
        Flapjack.redis.sadd(temp_set, values)

        keys = Flapjack.redis.keys("#{class_key}:*:attrs:#{key}")

        result = keys.inject([]) do |memo, k|
          if Flapjack.redis.sdiff(temp_set, k).empty?
            memo << load_from_key.call(k)
          end
          memo
        end

        Flapjack.redis.del(temp_set)
        result
      end

      # TODO change uses of Entity.all to EntityR.all.sort_by(&:name)

      # TODO change uses of Entity.find_by_name(N) to EntityR.find_by(:name, N)
    end

  end

end
