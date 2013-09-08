#!/usr/bin/env ruby

require 'forwardable'
require 'securerandom'

require 'active_support/concern'
require 'active_support/core_ext/object/blank'
require 'active_model'

require 'oj'
require 'redis-objects'

module Flapjack

  module Data

    module RedisRecord

      extend ActiveSupport::Concern

      included do
        include ActiveModel::AttributeMethods
        include ActiveModel::Dirty
        include ActiveModel::Validations

        attribute_method_suffix  "="  # attr_writers
        # attribute_method_suffix  ""   # attr_readers # DEPRECATED

        attr_accessor :logger

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

        # def has_one(*args)
        #   associate(HasOneAssociation, self, args)
        # end

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
          # when ::Flapjack::Data::RedisRecord::HasOneAssociation.name
          #   %Q{
          #     def #{name}
          #       #{name}_proxy
          #     end

          #     private

          #     def #{name}_proxy
          #       @#{name}_proxy ||=
          #         ::Flapjack::Data::RedisRecord::HasOneAssociation.new(self, "#{name}",
          #           :class => #{options[:class] ? options[:class].name : 'nil'} )
          #     end
          #   }
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
        @attrs = Redis::HashKey.new("#{self.class.send(:class_key)}:#{id}:attrs")
      end

      def refresh
        # TODO reset any AM::Dirty state
        @attributes = @attrs.inject({}) do |memo, (att, val)|
          memo[att] = (val.nil? || val.empty?) ? nil : Oj.load(val)
          memo
        end
      end

      # TODO limit to only those attribute names defined in define_attribute_methods
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

        regen_index.each do |key|
          next unless old_index_key = self.changes[key].first
          indexers[key].delete(old_index_key)
        end

        # store each value as the serialised JSON attribute (should be
        # the same for strings and numbers, but will handle arrays & hashes
        # as well)
        # TODO consider whether this is the best possible approach, or should
        # the representation be composed of various redis types, which would
        # mean a more complicated model to represent and store data types?
        serialised_attributes = attributes.inject({}) do |memo, (att, val)|
          value = case val
          when NilClass, ''
            nil
          when String, Integer, TrueClass, FalseClass
            Oj.dump(val)
          when Array, Hash
            # TODO capture JSON exception
            Oj.dump(val)
          else
            # TODO log warning
            nil
          end
          memo[att] = value
          memo
        end

        # uses hmset -- TODO limit to only those attribute names defined in
        # define_attribute_methods
        @attrs.bulk_set(serialised_attributes)

        regen_index.each do |key|
          next unless new_index_key = self.changes[key].last
          indexers[key][new_index_key] = @id
        end

        # ids is a set, so update won't create duplicates
        self.class.add_id(@id)

        # AM::Dirty
        @previously_changed = self.changes
        @changed_attributes.clear
        true
      end

      def destroy
        self.class.delete_id(@id)
        indexers = self.class.instance_variable_get('@indexers')
        (indexers || {}).each_pair do |key, indexer|
          next unless old_index_key = @attributes[key]
          indexer.delete(old_index_key)
        end
        @attrs.clear
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
          @record_ids = Redis::Set.new("#{parent.class.send(:class_key)}:#{parent.id}:#{name}")

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

      # class HasOneAssociation

      #   def initialize(parent, name, options = {})
      #     @hash = Redis::HashKey.new("#{parent.class.name.downcase}:#{parent.id}:#{name}")

      #     # TODO trap possible constantize error
      #     @associated_class = (options[:class] || name).classify.constantize
      #     raise 'Associated class does not mixin RedisRecord' unless @associated_class.included_modules.include?(RedisRecord)
      #   end

      #   # TODO shim to the @hash

      # end

    end
  end
end
