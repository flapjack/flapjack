#!/usr/bin/env ruby

# require 'flapjack/data/contact'

module Flapjack
  module Data
    class Message

      attr_reader :medium, :address, :duration, :contact, :rollup

      def self.push(queue, msg, opts = {})
        begin
          msg_json = Oj.dump(msg)
        rescue Oj::Error => e
          if opts[:logger]
            opts[:logger].warn("Error serialising message json: #{e}, message: #{message.inspect}")
          end
          msg_json = nil
        end

        if msg_json
          Flapjack.redis.multi do
            Flapjack.redis.lpush(queue, msg_json)
            Flapjack.redis.lpush("#{queue}_actions", "+")
          end
        end
      end

      def self.foreach_on_queue(queue, opts = {})
        while msg_json = Flapjack.redis.rpop(queue)
          begin
            message = ::Oj.load( msg_json )
          rescue Oj::Error => e
            if opts[:logger]
              opts[:logger].warn("Error deserialising message json: #{e}, raw json: #{msg_json.inspect}")
            end
            message = nil
          end

          yield message if block_given? && message
        end
      end

      def self.wait_for_queue(queue, opts = {})
        Flapjack.redis.brpop("#{queue}_actions")
      end

      def self.for_contact(contact, opts = {})
        self.new(:contact  => contact,
                 :medium   => opts[:medium],
                 :address  => opts[:address],
                 :duration => opts[:duration],
                 :rollup   => opts[:rollup])
      end

      def id
        return @id if @id
        t = Time.now
        # FIXME: consider using a UUID here
        # this is planned to be used as part of alert history keys
        @id = "#{self.object_id.to_i}-#{t.to_i}.#{t.tv_usec}"
      end

      def contents
        c = {'media'              => medium,
             'address'            => address,
             'id'                 => id,
             'rollup'             => rollup,
             'contact_id'         => contact.id,
             'contact_first_name' => contact.first_name,
             'contact_last_name'  => contact.last_name}
        c['duration'] = duration if duration
        c
      end

    private

      def initialize(opts = {})
        @contact  = opts[:contact]
        @medium   = opts[:medium]
        @address  = opts[:address]
        @duration = opts[:duration]
        @rollup   = opts[:rollup]
      end

    end
  end
end

