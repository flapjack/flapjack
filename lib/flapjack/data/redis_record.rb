#!/usr/bin/env ruby

require 'securerandom'

require 'active_support/concern'
require 'active_model'
require 'redis-objects'

module Flapjack

  module Data

    module RedisRecord

      extend ActiveSupport::Concern

      included do
        include ActiveModel::AttributeMethods
        include ActiveModel::Dirty
        include ActiveModel::Validations
        include Redis::Objects

        attribute_method_suffix  "="  # attr_writers
        # attribute_method_suffix  ""   # attr_readers # DEPRECATED

        instance_eval do
          # Evaluates in the context of the class -- so this is a
          # class instance variable. TODO accesses may need to be
          # synchronised to make this threadsafe
          @ids = Redis::Set.new("#{class_key}::ids")
        end

        attr_accessor :attributes
      end

      module ClassMethods

        def ids
          @ids.members
        end

        def add_id(id)
          @ids.add(id)
        end

        def delete_id(id)
          @ids.delete(id)
        end

        def exists?(id)
          @ids.include?(id)
        end

        def all
          @ids.collect {|id| load(id) }
        end

        def delete_all
          @ids.each {|id| load(id).destroy }
        end

        def find_by_id(id)
          return unless id && exists?(id)
          load(id)
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
          # TODO more complex logic, strip namespaces etc. -- see redis-objects #redis_prefix
          self.name.downcase
        end

        def load(id)
          attributes = redis.hgetall("#{class_key}:#{id}:attrs")
          self.new({:id => id.to_s}.merge(attributes))
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
        @id = attributes.delete(:id)
        @attributes = {}
        attributes.each_pair do |k, v|
          @attributes[k.to_s] = v
          send("#{k}_will_change!")
        end
        @attrs = Redis::HashKey.new("#{self.class.send(:class_key)}:#{@id}:attrs")
      end

      def id
        @id
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
        @id ||= SecureRandom.hex

        indexers = self.class.instance_variable_get('@indexers')
        regen_index = indexers.nil? ? [] : (self.changed & indexers.keys)

        regen_index.each do |key|
          next unless old_index_key = self.changes[key].first
          indexers[key].delete(old_index_key)
        end

        # uses hmset -- TODO limit to only those attribute names defined in
        # define_attribute_methods
        @attrs.bulk_set(attributes)

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
        indexers.each do |key, indexer|
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

        def initialize(parent, name, options = {})
          @record_ids = Redis::Set.new("#{parent.class.name.downcase}:#{parent.id}:#{name}")

          # TODO trap possible constantize error
          @associated_class = options[:class] || name.sub(/_ids$/, '').classify.constantize
          raise 'Associated class does not mixin RedisRecord' unless @associated_class.included_modules.include?(RedisRecord)
        end

        def <<(record)
          add(record)
          self  # for << 'a' << 'b'
        end

        def add(record)
          raise 'Invalid class' unless record.is_a?(@associated_class)
          ok = record.save # TODO check if exists? && !dirty, once AM::Dirty is included
          @record_ids.add(record.id) if ok && !@record_ids.include?(record.id)
        end

        def all
          @record_ids.map do |id|
            @associated_class.send(:load, id)
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
