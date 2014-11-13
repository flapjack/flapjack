#!/usr/bin/env ruby

require 'sandstorm/records/redis_record'

require 'flapjack/data/validators/id_validator'

require 'flapjack/data/check'
require 'flapjack/data/rule'

module Flapjack
  module Data
    class Tag

      include Sandstorm::Records::RedisRecord
      include ActiveModel::Serializers::JSON
      self.include_root_in_json = false

      define_attributes :name => :string

      has_and_belongs_to_many :checks,
        :class_name => 'Flapjack::Data::Check', :inverse_of => :tags

      has_and_belongs_to_many :rules,
        :class_name => 'Flapjack::Data::Rule', :inverse_of => :tags

      unique_index_by :name

      # TODO validate uniqueness of name

      validates_with Flapjack::Data::Validators::IdValidator

      def self.as_jsonapi(*tags)
        return [] if tags.empty?
        tag_ids = tags.map(&:id)

        check_ids = Flapjack::Data::Tag.intersect(:id => tag_ids).
          associated_ids_for(:checks)
        rule_ids = Flapjack::Data::Tag.intersect(:id => tag_ids).
          associated_ids_for(:rules)

        data = tags.collect do |tag|
          tag.as_json(:only => [:id, :name]).merge(:links => {
            :checks => check_ids[tag.id],
            :rules  => rule_ids[tag.id]
          })
        end
        return data unless data.size == 1
        data.first
      end

    end
  end
end
