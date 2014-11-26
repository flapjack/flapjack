#!/usr/bin/env ruby

require 'set'

require 'sandstorm/records/redis_record'

require 'flapjack/data/validators/id_validator'

require 'flapjack/data/route'

module Flapjack
  module Data
    class Rule

      include Sandstorm::Records::RedisRecord
      include ActiveModel::Serializers::JSON
      self.include_root_in_json = false

      # I've removed regex_* properties as they encourage loose binding against
      # names, which may change. Do client-side grouping and create a tag!

      define_attributes :is_specific => :boolean

      index_by :is_specific

      belongs_to :contact, :class_name => 'Flapjack::Data::Contact',
        :inverse_of => :rules

      has_and_belongs_to_many :tags, :class_name => 'Flapjack::Data::Tag',
        :inverse_of => :rules

      has_many :routes, :class_name => 'Flapjack::Data::Route',
        :inverse_of => :rule

      validates_with Flapjack::Data::Validators::IdValidator

      before_destroy :remove_child_records
      def remove_child_records
        self.class.lock(Flapjack::Data::Route) do
          self.routes.each  {|route| route.destroy }
        end
      end

      def self.jsonapi_attributes
        []
      end

      def self.jsonapi_singular_associations
        [:contact]
      end

      def self.jsonapi_multiple_associations
        [:routes, :tags]
      end
    end
  end
end

