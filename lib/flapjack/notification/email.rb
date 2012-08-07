#!/usr/bin/env ruby

require 'action_mailer'
require 'action_view'
require 'haml'
require 'haml/template/plugin'

module Flapjack
  class Notification::Email < Notification
    @queue = :email_notifications

    def self.sendit(notification)
      puts "Sending email notification now (not for realz)"

      notification_type  = notification['notification_type']
      contact_first_name = notification['contact_first_name']
      contact_last_name  = notification['contact_last_name']
      state              = notification['state']
      summary            = notification['summary']
      time               = notification['time']
      entity, check      = notification['event_id'].split(':')

      puts "Sending sms notification now"
      headline_map = {'problem'         => 'PROBLEM: ',
                      'recovery'        => 'RECOVERY: ',
                      'acknowledgement' => 'ACK: ',
                      'unknown'         => '',
                      ''                => '',
                     }

      headline = headline_map[notification_type] || ''

      notification['subject']  = "#{headline}'#{check}' on #{entity} is #{state.upcase}"
      Flapjack::Notification::Mailer.sender(notification)
    end

  end

  # FIXME: move this to a separate file
  ActionMailer::Base.raise_delivery_errors = true
  ActionMailer::Base.view_paths = File.dirname(__FILE__)
  ActionMailer::Base.smtp_settings[:address] = '127.0.0.1'
  class Notification::Mailer < ActionMailer::Base
    self.mailer_name = 'flapjack_mailer'

    def sender(notification)
      from     = 'flapjack@bulletproof.net'
      reply_to = 'flapjack@bulletproof.net'

      to                  = notification['address']
      subject             = notification['subject']

      @notification_type  = notification['notification_type']
      @contact_first_name = notification['contact_first_name']
      @contact_last_name  = notification['contact_last_name']
      @state              = notification['state']
      @summary            = notification['summary']
      @time               = notification['time']
      @entity, @check     = notification['event_id'].split(':')

      mail(:subject  => subject,
           :from     => from,
           :to       => to,
           :reply_to => reply_to) do |format|
        #format.text
        format.html
      end
    end

  end

end

