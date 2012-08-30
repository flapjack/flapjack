#!/usr/bin/env ruby

module Flapjack

  module Data

    class Contact

      # takes a check, looks up contacts that are interested in this check (or in the check's entity)
      # and returns an array of contact ids
      def self.find_all_for_entity_check(entity_check, options = {})
        logger = options[:logger]
        redis = options[:redis] # TODO error unless

        entity = entity_check.entity
        check = entity_check.check

        if logger
          logger.debug("contacts for #{entity.id} (#{entity}): " + redis.smembers("contacts_for:#{entity.id}").length.to_s)
          logger.debug("contacts for #{check}: " + redis.smembers("contacts_for:#{check}").length.to_s)
        end

        union = redis.sunion("contacts_for:#{entity.id}", "contacts_for:#{check}")
        logger.debug("contacts for union of #{entity.id} and #{check}: " + union.length.to_s) if logger
        union
      end

    end

  end

end
