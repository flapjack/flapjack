#!/usr/bin/env ruby

require 'securerandom'
require 'set'

require 'oj'
require 'active_support/concern'
require 'active_support/core_ext/object/blank'
require 'active_model'

require 'redis-objects'

# TODO port the redis-objects parts to raw redis calls, when things have
# stabilised

# TODO escape ids and index_keys -- shouldn't allow :

module Flapjack

  module Data

    module RedisRecord

      ATTRIBUTE_TYPES = {:string      => [String],
                         :integer     => [Integer],
                         :id          => [String],
                         :timestamp   => [Integer, DateTime],
                         :boolean     => [TrueClass, FalseClass],
                         :list        => [Enumerable],
                         :set         => [Set],
                         :hash        => [Hash],
                         :json_string => [String, Integer, Enumerable, Set, Hash]}

      COMPLEX_MAPPINGS = {:list       => Redis::List,
                          :set        => Redis::Set,
                          :hash       => Redis::HashKey}

      extend ActiveSupport::Concern

      included do
        include ActiveModel::AttributeMethods
        extend ActiveModel::Callbacks
        include ActiveModel::Dirty
        include ActiveModel::Serializers::JSON
        include ActiveModel::Validations

        attribute_method_suffix  "="  # attr_writers
        # attribute_method_suffix  ""   # attr_readers # DEPRECATED

        attr_accessor :logger

        validates_with Flapjack::Data::RedisRecord::TypeValidator

        # TODO Thread-local variables for class instance variables (@ids, @indexers)

        instance_eval do
          # Evaluates in the context of the class -- so this is a
          # class instance variable.
          @ids = Redis::Set.new("#{class_key}::ids")
        end

        attr_accessor :attributes

        define_attributes :id => :string
        # validates :id, :presence => true
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

        def intersect(opts = {})
          filter = Flapjack::Data::RedisRecord::Filter.new(@ids, self)
          filter.intersect(opts)
        end

        def union(opts = {})
          filter = Flapjack::Data::RedisRecord::Filter.new(@ids, self)
          filter.union(opts)
        end

        def find_by_id(id)
          return unless id && exists?(id.to_s)
          load(id.to_s)
        end

        # TODO validate that the key is one for a set property
        def find_by_set_intersection(key, *values)
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

        def attribute_types
          @attribute_types
        end

        protected

        def define_attributes(options = {})
          @attribute_types ||= {}
          options.each_pair do |key, value|
            raise "Unknown attribute type ':#{value}' for ':#{key}'" unless
              ATTRIBUTE_TYPES.include?(value)
            self.define_attribute_methods([key])
          end
          @attribute_types.update(options)
        end

        def indexed_attributes
          @indexed_attributes ||= []
        end

        # NB: key must be a string or boolean type, TODO validate this
        def index_by(*args)
          args.each do |arg|
            indexed_attributes << arg.to_s
            associate(IndexAssociation, self, [arg])
          end
          nil
        end

        def has_many(*args)
          associate(HasManyAssociation, self, args)
          nil
        end

        def has_sorted_set(*args)
          associate(HasSortedSetAssociation, self, args)
          nil
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

        # true.to_s == 'true' and false.to_s == false anyway, but if we need any
        # other normalized value for the indexers we can add the type here

        # TODO clean up method params, it's a mish-mash
        def associate(klass, parent, args)
          assoc = nil
          case klass.name
          when ::Flapjack::Data::RedisRecord::IndexAssociation.name
            name = args.first

            # TODO check method_defined? ( which relative to instance_eval ?)

            unless name.nil?
              assoc = %Q{
                def #{name}_index(value)
                  ret = #{name}_proxy_index
                  ret.value = value
                  ret
                end

                private

                def #{name}_proxy_index
                  @#{name}_proxy_index ||=
                    ::Flapjack::Data::RedisRecord::IndexAssociation.new(self, "#{class_key}", "#{name}")
                end
              }
              instance_eval assoc, __FILE__, __LINE__
            end

          when ::Flapjack::Data::RedisRecord::HasManyAssociation.name
            options = args.extract_options!
            name = args.first.to_s

            # TODO check method_defined? ( which relative to class_eval ? )

            unless name.nil?
              assoc = %Q{
                def #{name}
                  #{name}_proxy
                end

                def #{name}_ids
                  #{name}_proxy.ids
                end

                private

                def #{name}_proxy
                  @#{name}_proxy ||=
                    ::Flapjack::Data::RedisRecord::HasManyAssociation.new(self, "#{name}",
                      :class => #{options[:class] ? options[:class].name : 'nil'})
                end
              }
              class_eval assoc, __FILE__, __LINE__
            end
          when ::Flapjack::Data::RedisRecord::HasSortedSetAssociation
            options = args.extract_options
            name = args.first.to_s
            key = (options[:key] || :id).to_s

            # TODO check method_defined? ( which relative to class_eval ? )

            unless name.nil?
              assoc = %Q{
                def #{name}
                  #{name}_proxy
                end

                def #{name}_ids
                  #{name}_proxy.ids
                end

                private

                def #{name}_proxy
                  @#{name}_proxy ||=
                    ::Flapjack::Data::RedisRecord::HasSortedSetAssociation.new(self, "#{name}",
                      :class => #{options[:class] ? options[:class].name : 'nil'},
                      :key   => "#{key}")
                end
              }
              class_eval assoc, __FILE__, __LINE__
            end
          end

        end

      end

      def initialize(attributes = {})
        @attributes = {}
        attributes.each_pair do |k, v|
          self.send("#{k}=".to_sym, v)
        end
      end

      def persisted?
        !@attributes['id'].nil? && self.class.exists?(@attributes['id'])
      end

      def load(id)
        self.id = id
        refresh
      end

      def record_key
        "#{self.class.send(:class_key)}:#{self.id}"
      end

      def refresh
        # resets AM::Dirty changed state
        @previously_changed.clear unless @previously_changed.nil?
        @changed_attributes.clear unless @changed_attributes.nil?

        attr_types = self.class.attribute_types

        @attributes = {'id' => self.id}

        simple_attrs = @simple_attributes.inject({}) do |memo, (name, value)|
          if type = attr_types[name.to_sym]
            memo[name] = case type
            when :string
              value
            when :integer, :timestamp
              value.to_i
            when :boolean
              value.downcase == 'true'
            when :json_string
              value.blank? ? nil : Oj.dump(value)
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
              Set.new(redis_obj.members)
            when :hash
              redis_obj.all
            end
          end
          memo
        end

        @attributes.update(simple_attrs)
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

        self.id ||= SecureRandom.hex(16)

        idx_attrs = self.class.send(:indexed_attributes)

        indexed = self.changed & idx_attrs

        Flapjack.redis.multi

        indexed.each do |att|
          value = self.changes[att].first
          next if value.nil?
          self.class.send("#{att}_index", value).delete_id( @attributes['id'] )
        end

        simple_attrs  = {}
        complex_attrs = {}

        attr_types = self.class.attribute_types.reject {|k, v| k == :id}

        attr_types.each_pair do |name, type|
          value = @attributes[name.to_s]
          case type
          when :string, :integer
            simple_attrs[name.to_s] = value.blank? ? nil : value.to_s
          when :boolean
            simple_attrs[name.to_s] = (!!value).to_s
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

        indexed.each do |att|
          value = self.changes[att].last
          next if value.nil?
          self.class.send("#{att}_index", value).add_id( @attributes['id'] )
        end

        # ids is a set, so update won't create duplicates
        self.class.add_id(@attributes['id'])

        Flapjack.redis.exec

        # AM::Dirty
        @previously_changed = self.changes
        @changed_attributes.clear
        true
      end

      def destroy
        Flapjack.redis.multi
        self.class.delete_id(@attributes['id'])
        (self.attributes.keys & self.class.send(:indexed_attributes)).each {|att|
          self.class.send("#{att}_index", @attributes[att]).delete_id( @attributes['id'])
        }
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
        if att.to_s == 'id'
          raise "Cannot reassign id" unless @attributes['id'].nil?
          send("id_will_change!")
          @attributes['id'] = value.to_s
          @simple_attributes = Redis::HashKey.new("#{record_key}:attrs")
          @complex_attributes = self.class.attribute_types.inject({}) do |memo, (name, type)|
            if complex_type = Flapjack::Data::RedisRecord::COMPLEX_MAPPINGS[type]
              memo[name.to_s] = complex_type.new("#{record_key}:attrs:#{name}")
            end
            memo
          end
        else
          send("#{att}_will_change!")
          @attributes[att.to_s] = value
        end
      end

      # Simulate attribute readers from method_missing
      def attribute(att)
        @attributes[att.to_s]
      end

      # Used by ActiveModel to lookup attributes during validations.
      def read_attribute_for_validation(att)
        @attributes[att.to_s]
      end

      class IndexAssociation

        def initialize(parent, class_key, att)
          @set_indexers = {}
          @sorted_set_indexers = {}

          @parent = parent
          @class_key = class_key
          @attribute = att
        end

        def value=(value)
          @value = value
        end

        def delete_id(id)
          return unless (set_indexer = indexer_for_value(:set)) &&
            (sorted_set_indexer = indexer_for_value(:sorted_set))
          set_indexer.delete(id)
          sorted_set_indexer.delete(id)
        end

        def add_id(id)
          return unless (set_indexer = indexer_for_value(:set)) &&
            (sorted_set_indexer = indexer_for_value(:sorted_set))
          set_indexer.add(id)
          # TODO will score be relevant here? can we access timestamp?
          sorted_set_indexer.add(id, 1)
        end

        def key(type)
          return unless indexer = indexer_for_value(type)
          indexer.key
        end

        private

        def indexer_for_value(type)
          index_key = case @value
          when String, Symbol, TrueClass, FalseClass
            @value.to_s
          end
          return if index_key.nil?

          case type
          when :set
            unless @set_indexers[index_key]
              @set_indexers[index_key] = Redis::Set.new("#{@class_key}::by_#{@attribute}:set:#{index_key}")
            end
            @set_indexers[index_key]
          when :sorted_set
            unless @sorted_set_indexers[index_key]
              @sorted_set_indexers[index_key] = Redis::SortedSet.new("#{@class_key}::by_#{@attribute}:sorted_set:#{index_key}")
            end
            @sorted_set_indexers[index_key]
          end
        end

      end

      class HasSortedSetAssociation

        def initialize(parent, name, options = {})
          @key = options[:key]
          @record_keys = Redis::SortedSet.new("#{parent.record_key}:#{name.singularize}_#{options[:key].pluralize}")
        end

        def <<(record)
          add(record)
          self  # for << 'a' << 'b'
        end

        def add(*records)
          records.each do |record|
            raise 'Invalid class' unless record.is_a?(@associated_class)
            next unless record.save # TODO check if exists? && !dirty
            # TODO check this add
            @record_keys.add(@record.id, record.send(options[:key].to_sym))
          end
        end

        def delete(*records)
          records.each do |record|
            raise 'Invalid class' unless record.is_a?(@associated_class)
            @record_keys.delete(@record.id)
          end
        end

        def count
          Flapjack::Data::RedisRecord::Filter.new(@record_keys,
            @associated_class).count
        end

        def all
          Flapjack::Data::RedisRecord::Filter.new(@record_keys,
            @associated_class).all
        end

        def collect(&block)
          Flapjack::Data::RedisRecord::Filter.new(@record_keys,
            @associated_class).collect(block)
        end

        def each(&block)
          Flapjack::Data::RedisRecord::Filter.new(@record_keys,
            @associated_class).each(block)
        end

        def ids
          Flapjack::Data::RedisRecord::Filter.new(@record_keys,
            @associated_class).ids
        end
      end

      class HasManyAssociation

        def initialize(parent, name, options = {})
          @record_ids = Redis::Set.new("#{parent.record_key}:#{name.singularize}_ids")

          # TODO trap possible constantize error
          @associated_class = options[:class] || name.sub(/_ids$/, '').classify.constantize
          raise 'Associated class does not mixin RedisRecord' unless @associated_class.included_modules.include?(RedisRecord)
        end

        def intersect(opts = {})
          filter = Flapjack::Data::RedisRecord::Filter.new(@record_ids, @associated_class)
          filter.intersect(opts)
        end

        def union(opts = {})
          filter = Flapjack::Data::RedisRecord::Filter.new(@record_ids, @associated_class)
          filter.union(opts)
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

        def count
          Flapjack::Data::RedisRecord::Filter.new(@record_ids,
            @associated_class).count
        end

        def all
          Flapjack::Data::RedisRecord::Filter.new(@record_ids,
            @associated_class).all
        end

        def collect(&block)
          Flapjack::Data::RedisRecord::Filter.new(@record_ids,
            @associated_class).collect(block)
        end

        def each(&block)
          Flapjack::Data::RedisRecord::Filter.new(@record_ids,
            @associated_class).each(block)
        end

        def ids
          Flapjack::Data::RedisRecord::Filter.new(@record_ids,
            @associated_class).ids
        end
      end

      class Filter
        # NB: maps a Set-ish interface itself...

        def initialize(initial_set, associated_class)
          @initial_set = initial_set
          @associated_class = associated_class
          @steps = []
        end

        def intersect(opts = {})
          @steps += [:intersect, opts]
          self
        end

        def union(opts = {})
          @steps += [:union, opts]
          self
        end

        def count
          resolve_steps {|set| Flapjack.redis.smembers(temp_set)}
        end

        def all
          ids.map {|id| @associated_class.send(:load, id) }
        end

        def collect(&block)
          ids.collect do |id|
            block.call(@associated_class.send(:load, id))
          end
        end

        def each
          ids.each do |id|
            block.call(@associated_class.send(:load, id))
          end
        end

        def ids
          resolve_steps {|set| Flapjack.redis.smembers(set) }
        end

        private

        # TODO clean up to not use a temporary set if only doing one operation
        # (or possibly for the last operation) e.g. sunion instead of sunionstore

        # passes back the name of the temporary set with the ids resulting
        # from the applied steps; calling methods need to delete this set
        # when they have finished with it
        def resolve_steps(&block)
          return block.call(@initial_set.key) if @steps.empty?

          temp_set = "#{@associated_class.send(:class_key)}::tmp:#{SecureRandom.hex(16)}"

          idx_attrs = @associated_class.send(:indexed_attributes)

          initial = @initial_set ? @initial_set.key : nil

          @steps.each_slice(2) do |step|

            source_keys = []

            if initial
              source_keys << initial
              initial = nil
            end

            source_keys += step.last.inject([]) do |memo, (att, value)|
              if idx_attrs.include?(att.to_s)
                value = [value] unless value.is_a?(Enumerable)
                value.each do |val|
                  att_index = @associated_class.send("#{att}_index", val)

                  type = case @initial_set
                  when Redis::SortedSet
                    :sorted_set
                  when Redis::Set, nil
                    :set
                  end

                  memo << att_index.key(type)
                end
              end
              memo
            end

            case @initial_set
            when Redis::SortedSet
              case step.first
              when :union
                Flapjack.redis.zunionstore(temp_set, source_keys)
              when :intersect
                Flapjack.redis.zinterstore(temp_set, source_keys)
              end
            when Redis::Set, nil
              case step.first
              when :union
                Flapjack.redis.sunionstore(temp_set, *source_keys)
              when :intersect
                Flapjack.redis.sinterstore(temp_set, *source_keys)
              end
            end
          end
          ret = block.call(temp_set)
          Flapjack.redis.del(temp_set)
          ret
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
              count = (valid_type.size > 1) ? "one of " : ""
              type_str = valid_type.collect {|type| type.name }.join(", ")
              record.errors.add(name, "should be #{count}#{type_str} but is #{value.class.name}")
            end
          end
        end
      end
    end
  end
end
