#!/usr/bin/env ruby

# NB: use of redis.keys probably indicates we should maintain a data
# structure to avoid the need for this type of query

module Flapjack

  module Data

    class Contact

      attr_accessor :first_name, :last_name, :email, :media, :id

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

      def self.find_by_id(id, options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        raise "No id value passed" unless id
        logger = options[:logger]

        fn, ln, em = redis.hmget("contact:#{id}", 'first_name', 'last_name', 'email')
        me = redis.hgetall("contact_media:#{id}")

        pd_cred = self.pagerduty_credentials
        me[:pagerduty] = pd_cred unless pd_cred.nil?

        self.new(:first_name => fn, :last_name => ln,
          :email => em, :id => id, :media => me, :redis => redis )
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

      def pagerduty_credentials
        return unless service_key = @redis.hget("contact_media:#{self.id}", 'pagerduty')
        @redis.hgetall("contact_pagerduty:#{self.id}").
          merge('service_key' => service_key)
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
