#!/usr/bin/env ruby

require 'rubygems'
require 'net/smtp'
require 'tmail'
require 'log4r'

module Flapjack
  module Notifiers

    class Mailer

      def initialize(opts={})
        if opts[:from_address]
          @from_address = opts[:from_address]
        else
          raise ArgumentError, "from address must be provided"
        end
        @website_uri  = opts[:website_uri] ? opts[:website_uri].gsub(/\/$/, '') : "http://#{`hostname`}"
        @log = opts[:logger]
        @log ||= ::Log4r::Logger.new("notifier")
      end

      def notify(opts={})
        raise ArgumentError, "a recipient was not specified" unless opts[:who]
        raise ArgumentError, "a result was not specified" unless opts[:result]

        # potential FIXME: refactor TMail out entirely?
        mail = TMail::Mail.new
        mail.to = opts[:who].email
        mail.from = @from_address
        mail.subject = "Check: #{opts[:result].check_id}, Status: #{opts[:result].status}"
        mail.body = <<-DESC
          Check #{opts[:result].check_id} returned the status "#{opts[:result].status}".
          
          Here was the output: 
            #{opts[:result].output}
    
          You can respond to this issue at:
            #{@website_uri}/issue/#{opts[:result].check_id}
        DESC

        begin 
          Net::SMTP.start('localhost') do |smtp|
            return smtp.sendmail(mail.to_s, mail.from, mail.to)
          end
        rescue Errno::ECONNREFUSED
          @log.error("Couldn't establish connection to mail server!")
        end
      end
    
    end
  end
end
