#!/usr/bin/env ruby

module Flapjack

  module Data

    class Contact

      attr_accessor :first_name, :last_name, :email, :media, :id

      def self.all(options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        logger = options[:logger]

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

        fn = redis.hget("contact:#{id}", 'first_name')
        ln = redis.hget("contact:#{id}", 'last_name')
        em = redis.hget("contact:#{id}", 'email')

        media_keys = redis.hkeys("contact_media:#{id}")
        me = if media_keys.empty?
          {}
        else
          media_vals = redis.hmget("contact_media:#{id}", media_keys)
          Hash[ media_keys.zip(media_vals) ]
        end

        pagerduty_keys = redis.hkeys("contact_pagerduty:#{id}")
        unless pagerduty_keys.empty?
          pagerduty_vals = redis.hmget("contact_pagerduty:#{id}", pagerduty_keys)
          media_hash[:pagerduty] = Hash[ pagerduty_keys.zip(pagerduty_vals) ]
        end

        self.new(:first_name => fn, :last_name => ln,
          :email => em, :id => id, :media => me, :redis => redis )
      end

      # takes a check, looks up contacts that are interested in this check (or in the check's entity)
      # and returns an array of contact ids
      def self.find_all_for_entity_check(entity_check, options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        logger = options[:logger]

        entity = entity_check.entity
        check  = entity_check.check

        if logger
          logger.debug("contacts for #{entity.id} (#{entity.name}): " + redis.smembers("contacts_for:#{entity.id}").length.to_s)
          logger.debug("contacts for #{check}: " + redis.smembers("contacts_for:#{check}").length.to_s)
        end

        union = redis.sunion("contacts_for:#{entity.id}", "contacts_for:#{check}")
        logger.debug("contacts for union of #{entity.id} and #{check}: " + union.length.to_s) if logger
        union
      end

      def self.delete_all(options = {})
        raise "Redis connection not set" unless redis = options[:redis]

        redis.del( redis.keys("contact:*") +
                   redis.keys("contact_media:*") +
                   redis.keys("contact_pagerduty:*") +
                   redis.keys('contacts_for:*') )
      end

      # NB: should probably be called in the context of a Redis multi block; not doing so
      # here as calling classes may well be adding/updating multiple records in the one
      # operation
      def self.add(contact, options = {})
        raise "Redis connection not set" unless redis = options[:redis]

        redis.del("contact:#{contact['id']}")
        redis.del("contact_media:#{contact['id']}")
        redis.del("contact_pagerduty:#{contact['id']}")
        ['first_name', 'last_name', 'email'].each do |field|
          redis.hset("contact:#{contact['id']}", field, contact[field])
        end
        contact['media'].each_pair {|medium, address|
          case medium
          when 'pagerduty'
            redis.hset("contact_media:#{contact['id']}", medium, address['service_key'])
            redis.hset("contact_pagerduty:#{contact['id']}", 'subdomain', address['subdomain'])
            redis.hset("contact_pagerduty:#{contact['id']}", 'username',  address['username'])
            redis.hset("contact_pagerduty:#{contact['id']}", 'password',  address['password'])
          else
            redis.hset("contact_media:#{contact['id']}", medium, address)
          end
        }
      end

      def self.pagerduty_credentials_for_contact(contact, options = {})
        raise "Redis connection not set" unless redis = options[:redis]

        return unless service_key = redis.hget("contact_media:#{contact}", 'pagerduty')

        redis.hgetall("contact_pagerduty:#{contact}").
          merge('service_key' => service_key)
      end

      def name
        [(self.first_name || ''), (self.last_name || '')].join(" ").strip
      end

    private

      def initialize(options = {})
        raise "Redis connection not set" unless @redis = options[:redis]
        @first_name = options[:first_name]
        @last_name  = options[:last_name]
        @email      = options[:email]
        @media      = options[:media]
        @id         = options[:id]
      end

    end

  end

end
