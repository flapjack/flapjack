#!/usr/bin/env ruby

require 'xmpp4r-simple'

module Flapjack
  module Notifiers
    class Mock
    
      attr_accessor :log, :website_uri

      def initialize(opts={})
        @log = opts[:logger]
        @website_uri = opts[:website_uri]
      end
    
    end
  end
end

