#!/usr/bin/env ruby

require 'logger'
require 'redis'

# bugfix for webrick's assuming 1.8.7 Logger syntax
class ::Logger; alias_method :write, :<<; end

# Pretty sure XMUC is only constructed to initialise a MUC presence,
# so it's fine to add the extra 'no-history' stanza in any object created
require 'xmpp4r/query'
require 'xmpp4r/muc'

module Jabber
  module MUC
    class XMUC < ::Jabber::X

      def initialize(*arg)
        super(*arg)
        history = ::Jabber::XMPPElement.new('history')
        history.add_attributes({'maxstanzas' => '0'})
        self.add(history)
      end

    end
  end
end
