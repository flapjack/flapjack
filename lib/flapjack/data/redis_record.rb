#!/usr/bin/env ruby

require 'securerandom'
require 'set'

require 'active_support/concern'
require 'active_support/core_ext/object/blank'
require 'active_model'

require 'redis-objects'

# TODO port the redis-objects parts to raw redis calls, when things have
# stabilised

# TODO escape ids and index_keys -- shouldn't allow bare :

# TODO callbacks on before/after add/delete on association?

module Flapjack

  module Data

    module RedisRecord

      ATTRIBUTE_TYPES = {:string              => [String],
                         :integer             => [Integer],
                         :id                  => [String],
                         :timestamp           => [Integer, Time, DateTime],
                         :boolean             => [TrueClass, FalseClass],
                         :list                => [Enumerable],
                         :set                 => [Set],
                         :hash                => [Hash],
                         :json_string         => [String, Integer, Enumerable, Set, Hash]}

      COMPLEX_MAPPINGS = {:list         => Redis::List,
                          :set          => Redis::Set,
                          :hash         => Redis::HashKey}

      extend ActiveSupport::Concern

      included do
        include ActiveModel::AttributeMethods
        # extend ActiveModel::Callbacks
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
          Flapjack::Data::RedisRecord::Filter.new(@ids, self).intersect(opts)
        end

        def union(opts = {})
          Flapjack::Data::RedisRecord::Filter.new(@ids, self).union(opts)
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

        def has_one(*args)
          associate(HasOneAssociation, self, args)
          nil
        end

        def has_sorted_set(*args)
          associate(HasSortedSetAssociation, self, args)
          nil
        end

        def belongs_to(*args)
          associate(BelongsToAssociation, self, args)
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

            assoc_args = []

            if options[:class_name]
              assoc_args << %Q{:class_name => "#{options[:class_name]}"}
            end

            if options[:inverse_of]
              assoc_args << %Q{:inverse_of => :#{options[:inverse_of].to_s}}
            end

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
                    ::Flapjack::Data::RedisRecord::HasManyAssociation.new(self, "#{name}", #{assoc_args.join(', ')})
                end
              }
              class_eval assoc, __FILE__, __LINE__
            end

          when ::Flapjack::Data::RedisRecord::HasOneAssociation.name
            options = args.extract_options!
            name = args.first.to_s

            assoc_args = []

            if options[:class_name]
              assoc_args << %Q{:class_name => "#{options[:class_name]}"}
            end

            if options[:inverse_of]
              assoc_args << %Q{:inverse_of => :#{options[:inverse_of].to_s}}
            end

            # TODO check method_defined? ( which relative to class_eval ? )

            unless name.nil?
              assoc = %Q{
                def #{name}
                  #{name}_proxy.value
                end

                def #{name}=(obj)
                  #{name}_proxy.value = obj
                end

                private

                def #{name}_proxy
                  @#{name}_proxy ||= ::Flapjack::Data::RedisRecord::HasOneAssociation.new(self, "#{name}", #{assoc_args.join(', ')})
                end
              }
              class_eval assoc, __FILE__, __LINE__
            end

          when ::Flapjack::Data::RedisRecord::BelongsToAssociation.name
            options = args.extract_options!
            name = args.first.to_s

            assoc_args = []

            if options[:class_name]
              assoc_args << %Q{:class_name => "#{options[:class_name]}"}
            end

            if options[:inverse_of]
              assoc_args << %Q{:inverse_of => :#{options[:inverse_of].to_s}}
            end

            # TODO check method_defined? ( which relative to class_eval ? )

            unless name.nil?
              assoc = %Q{
                def #{name}
                  #{name}_proxy.value
                end

                def #{name}=(obj)
                  #{name}_proxy.value = obj
                end

                private

                def #{name}_proxy
                  @#{name}_proxy ||= ::Flapjack::Data::RedisRecord::BelongsToAssociation.new(self, "#{name}", #{assoc_args.join(', ')})
                end
              }
              class_eval assoc, __FILE__, __LINE__
            end

          when ::Flapjack::Data::RedisRecord::HasSortedSetAssociation.name
            options = args.extract_options!
            name = args.first.to_s

            assoc_args = []

            if options[:class_name]
              assoc_args << %Q{:class_name => "#{options[:class_name]}"}
            end

            if options[:inverse_of]
              assoc_args << %Q{:inverse_of => :#{options[:inverse_of].to_s}}
            end

            assoc_args << %Q{:key => "#{(options[:key] || :id).to_s}"}

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
                    ::Flapjack::Data::RedisRecord::HasSortedSetAssociation.new(self, "#{name}", #{assoc_args.join(', ')})
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
              value.to_s
            when :integer
              value.to_i
            when :timestamp
              Time.at(value.to_i)
            when :boolean
              value.downcase == 'true'
            when :json_string
              value.blank? ? nil : value.to_json
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
        return unless self.changed?
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
        remove_attrs = []

        attr_types = self.class.attribute_types.reject {|k, v| k == :id}

        attr_types.each_pair do |name, type|
          value = @attributes[name.to_s]
          if value.nil?
            remove_attrs << name.to_s
            next
          end
          case type
          when :string, :integer
            simple_attrs[name.to_s] = value.blank? ? nil : value.to_s
          when :timestamp
            simple_attrs[name.to_s] = value.blank? ? nil : value.to_i.to_f
          when :boolean
            simple_attrs[name.to_s] = (!!value).to_s
          when :list, :set, :hash
            redis_obj = @complex_attributes[name.to_s]
            Flapjack.redis.del(redis_obj.key)
            unless value.blank?
              case attr_types[name.to_sym]
              when :list
                Flapjack.redis.rpush(redis_obj.key, *value)
              when :set
                redis_obj.merge(*value.to_a)
              when :hash
                redis_obj.bulk_set(value)
              end
            end
          when :json_string
            simple_attrs[name.to_s] = value.blank? ? nil : value.to_json
          end
        end

        # uses hmset
        # TODO check that nil value deletes relevant hash key
        remove_attrs.each do |name|
          @simple_attributes.delete(name)
        end

        @simple_attributes.bulk_set(simple_attrs)

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

      def key(att)
        # TODO raise error if not a 'complex' attribute
        @complex_attributes[att.to_s].key
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
          @parent = parent
          @name = name
          @inverse = options[:inverse_of] ? options[:inverse_of].to_s : nil
          @associated_class = (options[:class_name] || name.classify).constantize
          @record_ids = Redis::SortedSet.new("#{parent.record_key}:#{name}_ids")
        end

        def intersect(opts = {})
          Flapjack::Data::RedisRecord::Filter.new(@record_ids, @associated_class).
            intersect(opts)
        end

        def union(opts = {})
          Flapjack::Data::RedisRecord::Filter.new(@record_ids, @associated_class).
            union(opts)
        end

        def intersect_range(start, finish, options = {})
          Flapjack::Data::RedisRecord::Filter.new(@record_ids, @associated_class).
            intersect_range(options.merge(:start => start, :end => finish,
                                          :by_score => options[:by_score]))
        end

        def union_range(start, finish, options = {})
          Flapjack::Data::RedisRecord::Filter.new(@record_ids, @associated_class).
            union_range(options.merge(:start => start, :end => finish,
                                      :by_score => options[:by_score]))
        end

        def <<(record)
          add(record)
          self  # for << 'a' << 'b'
        end

        def add(*records)
          records.each do |record|
            raise 'Invalid class' unless record.is_a?(@associated_class)
            # TODO next if already exists? in set
            record.save

            if @inverse
              inverse_id = Redis::HashKey.new("#{record.record_key}:belongs_to")
              inverse_id["#{@inverse}_id"] = @parent.id
            end

            @record_ids.add(record.id, record.send(@key.to_sym).to_i)
          end
        end

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

      class HasManyAssociation

        def initialize(parent, name, options = {})
          @record_ids = Redis::Set.new("#{parent.record_key}:#{name}_ids")
          @name = name
          @parent = parent
          @inverse = options[:inverse_of] ? options[:inverse_of].to_s : nil

          # TODO trap possible constantize error
          @associated_class = (options[:class_name] || name.classify).constantize
          raise 'Associated class does not mixin RedisRecord' unless @associated_class.included_modules.include?(RedisRecord)
        end

        def intersect(opts = {})
          Flapjack::Data::RedisRecord::Filter.new(@record_ids, @associated_class).
            intersect(opts)
        end

        def union(opts = {})
          Flapjack::Data::RedisRecord::Filter.new(@record_ids, @associated_class).
            union(opts)
        end

        def <<(record)
          add(record)
          self  # for << 'a' << 'b'
        end

        def add(*records)
          records.each do |record|
            raise 'Invalid class' unless record.is_a?(@associated_class)
            # TODO next if already exists? in set
            record.save

            # TODO validate that record.is_a?(@associated_class)
            if @inverse
              inverse_id = Redis::HashKey.new("#{record.record_key}:belongs_to")
              inverse_id["#{@inverse}_id"] = @parent.id
            end

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

      class HasOneAssociation

        def initialize(parent, name, options = {})
          @record_id = Redis::Value.new("#{parent.record_key}:#{name}_id")
          @parent = parent
          @inverse = options[:inverse_of] ? options[:inverse_of].to_s : nil

          # TODO trap possible constantize error
          @associated_class = (options[:class_name] || name.classify).constantize
          raise 'Associated class does not mixin RedisRecord' unless @associated_class.included_modules.include?(RedisRecord)
        end

        def value=(record)
          # TODO validate that record.is_a?(@associated_class)

          if @inverse
            inverse_id = Redis::HashKey.new("#{record.record_key}:belongs_to")
            inverse_id["#{@inverse}_id"] = @parent.id
          end

          @record_id.value = record.id
        end

        def value
          return unless id = @record_id.value
          @associated_class.send(:load, id)
        end
      end

      class BelongsToAssociation

        def initialize(parent, name, options = {})
          @record_ids = Redis::HashKey.new("#{parent.record_key}:belongs_to")
          @parent = parent
          @name = name

          @inverse = options[:inverse_of] ? options[:inverse_of].to_s : nil

          # TODO trap possible constantize error
          @associated_class = (options[:class_name] || name.classify).constantize
          raise 'Associated class does not mixin RedisRecord' unless @associated_class.included_modules.include?(RedisRecord)
        end

        def value=(record)
          # TODO validate that record.is_a?(@associated_class)

          if @inverse
            record.send("#{@inverse}=".to_sym, @parent) if record.respond_to?("#{@inverse}=".to_sym)
          else
            @record_ids["#{@name}_id"] = record.id
          end
        end

        def value
          return unless id = @record_ids["#{@name}_id"]
          @associated_class.send(:load, id)
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

        def intersect_range(opts = {})
          @steps += [:intersect_range, opts]
          self
        end

        def union_range(opts = {})
          @steps += [:union_range, opts]
          self
        end

        def count
          resolve_steps {|set, desc|
            case @initial_set
            when Redis::SortedSet
              Flapjack.redis.zcard(set)
            when Redis::Set, nil
              Flapjack.redis.scard(set)
            end
          }
        end

        def all
          ids.map {|id| @associated_class.send(:load, id) }
        end

        def first
          return unless first_id = ids.first
          @associated_class.send(:load, first_id)
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
          resolve_steps {|set, order_desc|
            case @initial_set
            when Redis::SortedSet
              Flapjack.redis.send((order_desc ? :zrevrange : :zrange), set, 0, -1)
            when Redis::Set, nil
              Flapjack.redis.smembers(set).sort
            end
          }
        end

        private

        # TODO possible candidate for moving to a stored Lua script in the redis server?

        # takes a block and passes the name of the temporary set to it; deletes
        # the temporary set once done
        # NB set case could use sunion/sinter for the last step, sorted set case can't
        def resolve_steps(&block)
          return block.call(@initial_set.key, false) if @steps.empty?

          source_set = @initial_set.key
          dest_set   = "#{@associated_class.send(:class_key)}::tmp:#{SecureRandom.hex(16)}"

          idx_attrs = @associated_class.send(:indexed_attributes)

          order_desc = nil

          @steps.each_slice(2) do |step|

            order_desc = false

            source_keys = []
            source_keys << source_set if (source_set == dest_set) || [:intersect, :intersect_range].include?(step.first)

            range_ids_set = nil

            if [:intersect, :union].include?(step.first)

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

            elsif [:intersect_range, :union_range].include?(step.first)

              range_ids_set = "#{@associated_class.send(:class_key)}::tmp:#{SecureRandom.hex(16)}"

              options = step.last

              start = options[:start]
              finish = options[:end]

              if options[:by_score]
                start = '-inf' if start.nil? || (start <= 0)
                finish = '+inf' if finish.nil? || (finish <= 0)
              else
                start = 0 if start.nil?
                finish = -1 if finish.nil?
              end

              args = [start, finish]

              order_desc = options[:order] && 'desc'.eql?(options[:order].downcase)
              if order_desc
                if options[:by_score]
                  query = :zrevrangebyscore
                  args = args.map(&:to_s).reverse
                else
                  query = :zrevrange
                end
              elsif options[:by_score]
                query = :zrangebyscore
                args = args.map(&:to_s)
              else
                query = :zrange
              end

              args << {:with_scores => :true}

              if options[:limit]
                args.last.update(:limit => [0, options[:limit].to_i])
              end

              args.unshift(source_set)

              range_ids_scores = Flapjack.redis.send(query, *args)

              unless range_ids_scores.empty?
                Flapjack.redis.zadd(range_ids_set, *(range_ids_scores.map(&:reverse)))
              end
              source_keys << range_ids_set
            end

            case @initial_set
            when Redis::SortedSet
              case step.first
              when :union, :union_range
                Flapjack.redis.zunionstore(dest_set, source_keys)
              when :intersect, :intersect_range
                Flapjack.redis.zinterstore(dest_set, source_keys)
              end
              Flapjack.redis.del(range_ids_set) unless range_ids_set.nil?
            when Redis::Set, nil
              case step.first
              when :union
                Flapjack.redis.sunionstore(dest_set, *source_keys)
              when :intersect
                Flapjack.redis.sinterstore(dest_set, *source_keys)
              end
            end
            source_set = dest_set
          end
          ret = block.call(dest_set, order_desc)
          Flapjack.redis.del(dest_set)

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
