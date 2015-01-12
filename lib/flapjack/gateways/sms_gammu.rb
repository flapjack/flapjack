#!/usr/bin/env ruby

require 'mysql2'
require 'em-synchrony'
require 'flapjack/data/alert'
require 'flapjack/utility'

module Flapjack
  module Gateways
    class SmsGammu
      INSERT_QUERY = <<-SQL
        INSERT INTO outbox (InsertIntoDB, Text, DestinationNumber, CreatorID)
        VALUES ('%s', '%s', '%s', '%s')
      SQL

      class << self

        include Flapjack::Utility

        def start
          @sent = 0

          if @config.nil? || (@config.respond_to?(:empty?) && @config.empty?)
            @logger.error "sms_gammu config is missing"
            return
          end

          @db = Mysql2::Client.new(:host     => @config["mysql_host"],
                                   :database => @config["mysql_database"],
                                   :username => @config["mysql_username"],
                                   :password => @config["mysql_password"])
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
            @db.query(INSERT_QUERY % [Time.now, message, to, from])
            @sent += 1
            @alert.record_send_success!
            @logger.debug "Sent SMS via Gammu"
          rescue => e
            @logger.error "Failed to send SMS via Gammu: #{e.class}, #{e.message}"
          end
        end

        def perform(contents)
          @logger.debug "Woo, got a notification to send out: #{contents.inspect}"

          @alert  = Flapjack::Data::Alert.new(contents, :logger => @logger)
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
      end
    end
  end
end
