#!/usr/bin/env ruby

require 'em-synchrony'
require "em-synchrony/mysql2"
require 'flapjack/data/alert'
require 'flapjack/utility'

module Flapjack
  module Gateways
    class SmsGammu
      INSERT_QUERY = <<-SQL
        INSERT INTO outbox (InsertIntoDB, TextDecoded, DestinationNumber, CreatorID, Class)
        VALUES ('%s', '%s', '%s', '%s', %s)
      SQL

      include Flapjack::Utility

      def initialize(opts = {})
        @config = opts[:config]
        @logger = opts[:logger]
        @redis_config = opts[:redis_config] || {}

        if @config.nil? || (@config.respond_to?(:empty?) && @config.empty?)
          @logger.error "sms_gammu config is missing"
          return
        end

        @redis = Flapjack::RedisPool.new(:config => @redis_config, :size => 1, :logger => @logger)

        @logger.info("starting")
        @logger.debug("new sms_gammu gateway pikelet with the following options: #{@config.inspect}")

        @sent = 0
      end

      def stop
        @logger.info("stopping")
        @should_quit = true

        redis_uri = @redis_config[:path] ||
          "redis://#{@redis_config[:host] || '127.0.0.1'}:#{@redis_config[:port] || '6379'}/#{@redis_config[:db] || '0'}"
        shutdown_redis = EM::Hiredis.connect(redis_uri)
        shutdown_redis.rpush(@config['queue'], Flapjack.dump_json('notification_type' => 'shutdown'))
      end

      def start
        @db = Mysql2::EM::Client.new(:host     => @config["mysql_host"],
                                     :database => @config["mysql_database"],
                                     :username => @config["mysql_username"],
                                     :password => @config["mysql_password"])

        queue = @config['queue']

        until @should_quit
          begin
            @logger.debug("sms_gammu gateway is going into blpop mode on #{queue}")
            deliver( Flapjack::Data::Alert.next(queue, :redis => @redis, :logger => @logger) )
          rescue => e
            @logger.error "Error generating or dispatching SMS Gammu message: #{e.class}: #{e.message}\n" +
              e.backtrace.join("\n")
          end
        end
      end

      def deliver(alert)
        @alert = alert
        address = @alert.address
        from    = @config["from"]
        message = prepare_message
        errors  = []

        [[from,    "SMS from address is missing"],
         [address, "SMS address is missing"]].each do |val_err|

          next unless val_err.first.nil? || (val_err.first.respond_to?(:empty?) && val_err.first.empty?)
          errors << val_err.last
        end

        unless errors.empty?
          errors.each {|err| @logger.error err }
          return
        end

        send_message(message, from, address)
      rescue => e
        @logger.error "Error generating or delivering sms to #{contents['address']}: #{e.class}: #{e.message}"
        @logger.error e.backtrace.join("\n")
        raise
      end

      def prepare_message
        message_type  = @alert.rollup ? 'rollup' : 'alert'
        template_path = @config['templates']["#{message_type}.text"]
        template      = ERB.new(File.read(template_path), nil, '-')

        begin
          message = template.result(binding).chomp
          truncate(message, 159)
        rescue => e
          @logger.error "Error while excuting the ERB for an sms: " +
            "ERB being executed: #{template_path}"
          raise
        end
      end

      def send_message(message, from, to)
        begin
          @db.query(INSERT_QUERY % [Time.now, message, to, from, 1])
          @sent += 1
          @alert.record_send_success!
          @logger.debug "Sent SMS via Gammu"
        rescue => e
          @logger.error "Failed to send SMS via Gammu: #{e.class}, #{e.message}"
        end
      end

    end
  end
end
