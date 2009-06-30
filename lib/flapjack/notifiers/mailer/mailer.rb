#!/usr/bin/env ruby

require 'rubygems'
require 'net/smtp'
require 'mailfactory'

module Flapjack
  module Notifiers

    class Mailer

      def initialize(opts={})
        @from_address = opts[:from_address]
      end

      def notify(opts={})
        raise unless (opts[:who] && opts[:result])
    
        mail = MailFactory.new
        mail.to = opts[:who].email
        mail.from = @from_address
        mail.subject = "Check: #{opts[:result].id}, Status: #{opts[:result].status}"
        mail.text = <<-DESC
          Check #{opts[:result].id} returned the status "#{opts[:result].status}".
          
          Here was the output: 
            #{opts[:result].output}
    
          You can respond to this issue at:
            http://localhost:4000/issue/#{opts[:result].object_id * -1}
        DESC
    
        Net::SMTP.start('localhost') do |smtp|
          smtp.sendmail(mail.to_s, mail.from, mail.to)
        end
      end
    
    end
  end
end
