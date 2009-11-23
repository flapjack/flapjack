#!/usr/bin/env ruby

require 'xmpp4r'

module Flapjack
  module Notifiers
    class Xmpp
    
      def initialize(opts={})
    
        @jid = opts[:jid]
        @password = opts[:password]
        @log = opts[:logger]
        unless @jid && @password 
          raise ArgumentError, "You have to provide a username and password"
        end

        begin 
          @xmpp = Jabber::Client.new(@jid)
          @xmpp.connect
          @xmpp.auth(@password)
        rescue SocketError => e
          @log.error("XMPP: #{e.message}")
        end
    
      end
    
      def notify(opts={})
    
        raise ArgumentError, "a recipient was not specified" unless opts[:who] 
        raise ArgumentError, "a result was not specified" unless opts[:result]
    
        text = <<-DESC
          Check #{opts[:result].check_id} returned the status "#{opts[:result].status}".
            http://localhost:4000/checks/#{opts[:result].check_id}
        DESC
   
        message = Jabber::Message.new(opts[:who].jid, text)
        @xmpp.send(message)
    
      end
    
    end
  end
end

