#!/usr/bin/env ruby

require 'action_mailer'
require 'action_view'
require 'haml'
require 'haml/template/plugin'



module Flapjack
  class Notification::Email < Notification
    @queue = :email_notifications

    def self.sendit(notification)

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
      @log.debug "Flapjack::Notification::Email#sendit is calling Flapjack::Notification::Mailer.sender, notification_id: #{notification['id']}"
      Flapjack::Notification::Mailer.sender(notification, @log).deliver
    end

  end

  ActionMailer::Base.raise_delivery_errors = true
  ActionMailer::Base.view_paths = File.dirname(__FILE__)
  ActionMailer::Base.delivery_method = :smtp
  ActionMailer::Base.smtp_settings = { :address => "127.0.0.1",
                                       :port => 25,
                                       :enable_starttls_auto => false }

  # FIXME: move this to a separate file
  class Notification::Mailer < ActionMailer::Base
    self.mailer_name = 'flapjack_mailer'

    def sender(notification, log)
      fqdn     = `/bin/hostname -f`.chomp
      from     = "flapjack@#{fqdn}"
      log.debug("flapjack_mailer: set from to #{from}")
      reply_to = from

      to                  = notification['address']
      subject             = notification['subject']

      log.debug("Flapjack::Notification::Mailer #{notification['id']} to: #{to} subject: #{subject}")

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
        format.text
        format.html
      end
    end

  end

end

