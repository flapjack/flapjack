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

      def self.as_jsonapi(unwrap, *rules)
        return [] if rules.empty?
        rule_ids = rules.map(&:id)

        # contact_ids = Flapjack::Data::Rule.intersect(:id => rule_ids).
        #   associated_ids_for(:contact)
        # tag_ids = Flapjack::Data::Rule.intersect(:id => rule_ids).
        #   associated_ids_for(:tags)
        # route_ids = Flapjack::Data::Rule.intersect(:id => rule_ids).
        #   associated_ids_for(:routes)

        data = rules.collect do |rule|
          rule.as_json

          #   rule.as_json(:contact_ids => [linked_contact_ids[rule.id]],
          #                :tag_ids => linked_tag_ids,
          #                :route_ids => linked_route_ids[rule.id]
          #               )

          # :links => {
            # :contacts  => opts[:contact_ids] || [],
            # :tags      => opts[:tag_ids]     || [],
            # :routes    => opts[:route_ids]   || [],
          # }

        #     (:contact_ids => contact_ids[medium.id],
        #      :route_ids => route_ids[medium.id])
        end
        return data unless (data.size == 1) && unwrap
        data.first
      end

    end
  end
end

