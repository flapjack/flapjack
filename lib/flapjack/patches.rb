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

# OpenSSL sockets have ASCII-8BIT encoding, and XMPP4R doesn't
# cast to UTF-8 properly TODO need to test this with different
# external encodings
require 'openssl'
require 'rexml/parsers/sax2parser'

module REXML
  module Parsers
    class SAX2Parser

      alias_method :orig_initialize, :initialize

      def initialize(source)
        unless source.is_a?(OpenSSL::SSL::SSLSocket)
          orig_initialize( source )
          return
        end
        io_source = REXML::IOSource.new(source)
        io_source.instance_variable_set('@force_utf8', true)
        orig_initialize( io_source )
      end

    end
  end
end
