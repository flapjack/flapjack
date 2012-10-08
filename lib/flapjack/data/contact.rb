#!/usr/bin/env ruby

# NB: use of redis.keys probably indicates we should maintain a data
# structure to avoid the need for this type of query

require 'set'

module Flapjack

  module Data

    class Contact

      attr_accessor :first_name, :last_name, :email, :media, :pagerduty_credentials, :id

      def self.all(options = {})
        raise "Redis connection not set" unless redis = options[:redis]

        contact_keys = redis.keys('contact:*')

        contact_keys.inject([]) {|ret, k|
          k =~ /^contact:(\d+)$/
          id = $1
          contact = self.find_by_id(id, :redis => redis)
          ret << contact if contact
          ret
        }
      end

      def self.delete_all(options = {})
        raise "Redis connection not set" unless redis = options[:redis]

        redis.del( redis.keys("contact:*") +
                   redis.keys("contact_media:*") +
                   redis.keys("contact_pagerduty:*") +
                   redis.keys('contacts_for:*') )
      end

      def self.find_by_id(id, options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        raise "No id value passed" unless id
        logger = options[:logger]

        fn, ln, em = redis.hmget("contact:#{id}", 'first_name', 'last_name', 'email')
        me = redis.hgetall("contact_media:#{id}")

        # similar to code in instance method pagerduty_credentials
        pc = nil
        if service_key = redis.hget("contact_media:#{id}", 'pagerduty')
          pc = redis.hgetall("contact_pagerduty:#{id}").merge('service_key' => service_key)
        end

        self.new(:first_name => fn, :last_name => ln,
          :email => em, :id => id, :media => me, :pagerduty_credentials => pc, :redis => redis )
      end


      # NB: should probably be called in the context of a Redis multi block; not doing so
      # here as calling classes may well be adding/updating multiple records in the one
      # operation
      # TODO maybe return the instantiated Contact record?
      def self.add(contact, options = {})
        raise "Redis connection not set" unless redis = options[:redis]

        redis.del("contact:#{contact['id']}",
                  "contact_media:#{contact['id']}",
                  "contact_pagerduty:#{contact['id']}")

        redis.hmset("contact:#{contact['id']}",
                    *['first_name', 'last_name', 'email'].collect {|f| [f, contact[f]]})

        unless contact['media'].nil?
          contact['media'].each_pair {|medium, address|
            case medium
            when 'pagerduty'
              redis.hset("contact_media:#{contact['id']}", medium, address['service_key'])
              redis.hmset("contact_pagerduty:#{contact['id']}",
                          *['subdomain', 'username', 'password'].collect {|f| [f, address[f]]})
            else
              redis.hset("contact_media:#{contact['id']}", medium, address)
            end
          }
        end
      end

      def pagerduty_credentials
        return unless service_key = @redis.hget("contact_media:#{self.id}", 'pagerduty')
        @redis.hgetall("contact_pagerduty:#{self.id}").
          merge('service_key' => service_key)
      end

      def entities_and_checks
        @redis.keys('contacts_for:*').inject({}) {|ret, k|
          if @redis.sismember(k, self.id)
            if k =~ /^contacts_for:([a-zA-Z0-9][a-zA-Z0-9\.\-]*[a-zA-Z0-9])(?::(\w+))?$/
              entity_id = $1
              check = $2

              unless ret.has_key?(entity_id)
                ret[entity_id] = {}
                if entity_name = @redis.hget("entity:#{entity_id}", 'name')
                  entity = Flapjack::Data::Entity.new(:name => entity_name,
                             :id => entity_id, :redis => @redis)
                  ret[entity_id][:entity] = entity
                end
                # using a set to ensure unique check values
                ret[entity_id][:checks] = Set.new
              end

              if check
                # just add this check for the entity
                ret[entity_id][:checks] |= check
              else
                # registered for the entity so add all checks
                ret[entity_id][:checks] |= entity.check_list
              end
            end
          end
          ret
        }.values
      end

      def name
        [(self.first_name || ''), (self.last_name || '')].join(" ").strip
      end

    private

      def initialize(options = {})
        raise "Redis connection not set" unless @redis = options[:redis]
        [:first_name, :last_name, :email, :media, :id].each do |field|
          instance_variable_set(:"@#{field.to_s}", options[field])
        end
      end

    end

  end

end
