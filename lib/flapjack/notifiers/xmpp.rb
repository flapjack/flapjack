#!/usr/bin/env ruby

require 'xmpp4r-simple'

module Flapjack
  module Notifiers
    class Xmpp
    
      def initialize(opts={})
    
        @jid = opts[:jid]
        @password = opts[:password]
        unless @jid && @password 
          raise ArgumentError, "You have to provide a username and password"
        end
        @xmpp = Jabber::Simple.new(@jid, @password)
    
      end
    
      def notify!(opts={})
    
        raise unless opts[:who] && opts[:result]
    
        message = <<-DESC
          Check #{opts[:result].id} returned the status "#{opts[:result].status}".
            http://localhost:4000/issue/#{opts[:result].object_id * -1}
        DESC
    
        @xmpp.deliver(opts[:who].jid, message)
    
      end
    
    end
  end
end

