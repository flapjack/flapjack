#!/usr/bin/env ruby

require 'forwardable'
require 'securerandom'
require 'set'

require 'active_support/concern'
require 'active_support/core_ext/object/blank'
require 'active_model'

require 'oj'
require 'redis-objects'

# TODO port the redis-objects parts to raw redis calls, when things have
# stabilised

module Flapjack

  module Data

    module RedisRecord

      ATTRIBUTE_TYPES = {:string      => [String],
                         :integer     => [Integer],
                         :boolean     => [TrueClass, FalseClass],
                         :list        => [Enumerable],
                         :set         => [Set],
                         :hash        => [Hash],
                         :json_string => [String, Integer, Enumerable, Set, Hash]}

      COMPLEX_MAPPINGS = {:list => Redis::List,
                          :set  => Redis::Set,
                          :hash => Redis::HashKey}

      extend ActiveSupport::Concern

      included do
        include ActiveModel::AttributeMethods
        include ActiveModel::Dirty
        include ActiveModel::Validations

        attribute_method_suffix  "="  # attr_writers
        # attribute_method_suffix  ""   # attr_readers # DEPRECATED

        attr_accessor :logger

        validates_with Flapjack::Data::RedisRecord::TypeValidator

        instance_eval do
          # Evaluates in the context of the class -- so this is a
          # class instance variable. TODO accesses may need to be
          # synchronised to make this threadsafe
          @ids = Redis::Set.new("#{class_key}::ids")
        end

        attr_accessor :attributes
      end

      module ClassMethods

        def count
          @ids.count
        end

        def ids
          @ids.members
        end

        def add_id(id)
          @ids.add(id.to_s)
        end

        def delete_id(id)
          @ids.delete(id.to_s)
        end

        def exists?(id)
          @ids.include?(id.to_s)
        end

        def all
          @ids.collect {|id| load(id) }
        end

        def delete_all
          @ids.each {|id| load(id).destroy }
        end

        def find_by_id(id)
          return unless id && exists?(id.to_s)
          load(id.to_s)
        end

        def find_by(key, value)
          return unless @indexers.has_key?(key.to_s)
          id = @indexers[key.to_s][value.to_s]
          find_by_id(id)
        end

        def attribute_types
          @attribute_types
        end

        protected

        def define_attributes(options = {})
          @attribute_types ||= {}
          options.each_pair do |key, value|
            raise "Unknown attribute type ':#{value}' for ':#{key}'" unless
              ATTRIBUTE_TYPES.include?(value)
              self.define_attribute_methods [key]
          end
          @attribute_types.update(options)
        end

        def index_by(*args)
          @indexers ||= {}
          idxs = args.inject({}) do |memo, arg|
            memo[arg.to_s] = Redis::HashKey.new("#{class_key}:by_#{arg}")
            memo
          end
          @indexers.update(idxs)
        end

        def has_many(*args)
          associate(HasManyAssociation, self, args)
        end

        private

        def class_key
          self.name.underscore
        end

        def load(id)
          object = self.new
          object.load(id)
          object
        end

        def associate(klass, parent, args)
          options = args.extract_options!
          name = args.first.to_s

          return if name.nil? || method_defined?(name)

          assoc = case klass.name
          when ::Flapjack::Data::RedisRecord::HasManyAssociation.name
            %Q{
              def #{name}
                #{name}_proxy
              end

              def #{name}_ids
                #{name}_proxy.ids
              end

              private

              def #{name}_proxy
                @#{name}_proxy ||=
                  ::Flapjack::Data::RedisRecord::HasManyAssociation.new(self, "#{name.singularize}_ids",
                    :class => #{options[:class] ? options[:class].name : 'nil'} )
              end
            }
          end

          return if assoc.nil?
          class_eval assoc, __FILE__, __LINE__
        end

      end

      def initialize(attributes = {})
        if id = attributes.delete(:id)
          self.id = id
        end

        @attributes = {}
        attributes.each_pair do |k, v|
          send("#{k}_will_change!")
          @attributes[k.to_s] = v
        end
      end

      def load(id)
        self.id = id
        refresh
      end

      def id
        @id
      end

      def id=(id)
        raise "Cannot reassign id" unless @id.nil?
        @id = id
        @simple_attributes = Redis::HashKey.new("#{record_key}:attrs")
        @complex_attributes = self.class.attribute_types.inject({}) do |memo, (name, type)|
          if complex_type = Flapjack::Data::RedisRecord::COMPLEX_MAPPINGS[type]
            memo[name.to_s] = complex_type.new("#{record_key}:attrs:#{name}")
          end
          memo
        end
      end

      def record_key
        "#{self.class.send(:class_key)}:#{id}"
      end

      def refresh
        # resets AM::Dirty changed state
        @previously_changed.clear unless @previously_changed.nil?
        @changed_attributes.clear unless @changed_attributes.nil?

        attr_types = self.class.attribute_types

        @attributes = @simple_attributes.inject({}) do |memo, (name, value)|
          if type = attr_types[name.to_sym]
            memo[name] = case type
            when :string
              value
            when :integer
              value.to_i
            when :boolean
              (value.to_i == 1)
            when :json_string
              Oj.dump(value)
            end
          end
          memo
        end

        complex_attrs = @complex_attributes.inject({}) do |memo, (name, redis_obj)|
          if type = attr_types[name.to_sym]
          memo[name] = case type
            when :list
              redis_obj.values
            when :set
              redis_obj.members
            when :hash
              redis_obj.all
            end
          end
          memo
        end
        @attributes.update(complex_attrs)
      end

      # TODO limit to only those attribute names defined in define_attributes
      def update_attributes(attributes = {})
        attributes.each_pair do |att, v|
          unless value == @attributes[att.to_s]
            @attributes[att.to_s] = v
            send("#{att}_will_change!")
          end
        end
        save
      end

      def save
        return false unless valid?

        self.id ||= SecureRandom.hex

        indexers = self.class.instance_variable_get('@indexers')
        regen_index = indexers.nil? ? [] : (self.changed & indexers.keys)

        Flapjack.redis.multi

        regen_index.each do |key|
          next unless old_index_key = self.changes[key].first
          indexers[key].delete(old_index_key)
        end

        simple_attrs  = {}
        complex_attrs = {}

        attr_types = self.class.attribute_types

        attr_types.each_pair do |name, type|
          value = @attributes[name.to_s]
          case type
          when :string, :integer
            simple_attrs[name.to_s] = value.blank? ? nil : value.to_s
          when :boolean
            simple_attrs[name.to_s] = value.blank? ? nil : (!!value ? '1' : '0')
          when :list, :set, :hash
            complex_attrs[name.to_s] = value
          when :json_string
            simple_attrs[name.to_s] = value.blank? ? nil : Oj.dump(value)
          end
        end

        # uses hmset
        # TODO check that nil value deletes relevant hash key
        @simple_attributes.bulk_set(simple_attrs)

        complex_attrs.each_pair do |name, value|
          redis_obj = @complex_attributes[name.to_s]
          Flapjack.redis.del(redis_obj.key)
          next if value.blank?
          case attr_types[name.to_sym]
          when :list
            Flapjack.redis.rpush(redis_obj.key, *value)
          when :set
            redis_obj.merge(*value.to_a)
          when :hash
            redis_obj.bulk_set(value)
          end
        end

        regen_index.each do |key|
          next unless new_index_key = self.changes[key].last
          indexers[key][new_index_key] = @id
        end

        # ids is a set, so update won't create duplicates
        self.class.add_id(@id)

        Flapjack.redis.exec

        # AM::Dirty
        @previously_changed = self.changes
        @changed_attributes.clear
        true
      end

      def destroy
        Flapjack.redis.multi
        self.class.delete_id(@id)
        indexers = self.class.instance_variable_get('@indexers')
        (indexers || {}).each_pair do |key, indexer|
          next unless old_index_key = @attributes[key]
          indexer.delete(old_index_key)
        end
        @simple_attributes.clear
        @complex_attributes.values do |redis_obj|
          Flapjack.redis.del(redis_obj.key)
        end
        Flapjack.redis.exec
      end

      private

      # http://stackoverflow.com/questions/7613574/activemodel-fields-not-mapped-to-accessors
      #
      # Simulate attribute writers from method_missing
      def attribute=(att, value)
        return if value == @attributes[att.to_s]
        send("#{att}_will_change!")
        @attributes[att.to_s] = value
      end

      # Simulate attribute readers from method_missing
      def attribute(att)
        @attributes[att.to_s]
      end

      # Used by ActiveModel to lookup attributes during validations.
      def read_attribute_for_validation(att)
        @attributes[att.to_s]
      end

      class HasManyAssociation

        extend Forwardable

        def initialize(parent, name, options = {})
          @record_ids = Redis::Set.new("#{parent.record_key}:#{name}")

          # TODO trap possible constantize error
          @associated_class = options[:class] || name.sub(/_ids$/, '').classify.constantize
          raise 'Associated class does not mixin RedisRecord' unless @associated_class.included_modules.include?(RedisRecord)
        end

        def <<(record)
          add(record)
          self  # for << 'a' << 'b'
        end

        def add(*records)
          records.each do |record|
            raise 'Invalid class' unless record.is_a?(@associated_class)
            next unless record.save # TODO check if exists? && !dirty
            @record_ids.add(record.id)
          end
        end

        # TODO support dependent delete, for now just deletes the association
        def delete(*records)
          records.each do |record|
            raise 'Invalid class' unless record.is_a?(@associated_class)
            @record_ids.delete(record.id)
          end
        end

        # is there a neater way to do the next four? some mix of delegation & ...
        def count
          @record_ids.count
        end

        def all
          @record_ids.map do |id|
            @associated_class.send(:load, id)
          end
        end

        def collect(&block)
          @record_ids.collect do |id|
            block.call( @associated_class.send(:load, id) )
          end
        end

        def each(&block)
          @record_ids.each do |id|
            block.call( @associated_class.send(:load, id) )
          end
        end

        def ids
          @record_ids.members
        end

      end

      class TypeValidator < ActiveModel::Validator
        def validate(record)
          attr_types = record.class.attribute_types

          attr_types.each_pair do |name, type|
            value = record.send(name)
            next if value.nil?
            valid_type = Flapjack::Data::RedisRecord::ATTRIBUTE_TYPES[type]
            unless valid_type.any? {|type| value.is_a?(type) }
              count = (valid_type.size > 1) ? "one of" : "a"
              type_str = valid_type.collect {|type| type.name }.join(", ")
              record.errors.add(name, "should be #{count} #{type_str} but is a #{value.class.name}")
            end
          end
        end
      end
    end
  end
end
