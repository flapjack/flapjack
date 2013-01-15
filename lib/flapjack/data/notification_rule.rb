#!/usr/bin/env ruby

module Flapjack
  module Data
    class NotificationRule

      attr_accessor :tags

      def match?(event, contact, media)
        return false unless entity_match?
        return false unless time_match?

        return true
      end


    private
      def initialize(opts)
        @entity_tags       = opts[:service_tags] || nil
        @entities          = opts[:entities] || nil
        @time_restrictions = opts[:time_restrictions] || nil
        @warning_media     = opts[:warning_media] || nil
        @critical_media    = opts[:critical_media] || nil
      end

      # @warning_media  = [ 'email' ]
      # @critical_media = [ 'email', 'sms' ]

      # tags or entity names match?
      # nil @entity_tags and nil @entities matches
      def entity_match?

      end

      # time restrictions match?
      # nil @time_restrictions matches
      def time_match?

      end


    end
  end
end

