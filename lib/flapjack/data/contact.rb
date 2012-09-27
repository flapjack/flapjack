#!/usr/bin/env ruby

module Flapjack

  module Data

    class Contact

      attr_accessor :first_name, :last_name, :email, :media

      def self.all(options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        logger = options[:logger]

        contact_keys = redis.keys('contact:*')

        contact_keys.inject([]) {|ret, k|
          k =~ /^contact:(\d+)$/
          id = $1
          contact = self.find_by_id(id.to_i, :redis => redis)
          ret << contact if contact
          ret
        }
      end

      # TODO maybe store a reverse mapping of contacts by email address
      # (would make this query quicker)
      def self.find_by_email(email, options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        raise "No email value passed" unless id
        logger = options[:logger]

        contact_keys = redis.keys('contact:*')

        return unless email_key = contact_keys.detect {|k|
          ck_email = redis.hget(k, 'email')
          email == ck_email
        }

        email_key =~ /^contact:(\d+)$/
        id = $1

        self.find_by_id(id.to_i, :redis => redis)
      end

      def self.find_by_id(id, options = {})
        raise "Redis connection not set" unless redis = options[:redis]
        raise "No id value passed" unless id
        logger = options[:logger]

        first_name = redis.hget("contact:#{id}", 'first_name')
        last_name  = redis.hget("contact:#{id}", 'last_name')
        email      = redis.hget("contact:#{id}", 'email')

        Contact.new(:first_name => first_name,
          :last_name => last_name, :email => email, :id => id.to_i)
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

      # NB: should probably be called in the context of a Redis multi block; not doing so
      # here as calling classes may well be adding/updating multiple records in the one
      # operation
      def self.add(contact, options = {})
        raise "Redis connection not set" unless redis = options[:redis]

        redis.del("contact:#{contact['id']}")
        redis.del("contact_media:#{contact['id']}")
        redis.del("contact_pagerduty:#{contact['id']}")
        redis.hset("contact:#{contact['id']}", 'first_name', contact['first_name'])
        redis.hset("contact:#{contact['id']}", 'last_name',  contact['last_name'])
        redis.hset("contact:#{contact['id']}", 'email',      contact['email'])
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

    end

  end

end
