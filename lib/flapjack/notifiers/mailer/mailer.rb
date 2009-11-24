#!/usr/bin/env ruby

require 'rubygems'
require 'net/smtp'
require 'tmail'

module Flapjack
  module Notifiers

    class Mailer

      attr_accessor :log, :from_address

      def initialize(opts={})
        @log = opts[:log]
        @from_address = opts[:from_address]
        @website_uri = opts[:website_uri]
        
        raise ArgumentError, "from address must be provided" unless @from_address
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
