# fix for deprecation warning introduced by
# https://bugs.ruby-lang.org/issues/7688 ; remove when fixed in xmpp4r
if (RUBY_VERSION.split('.') <=> ['2', '2', '0']) >= 0
  require 'xmpp4r'
  require 'xmpp4r/jid'
  require 'xmpp4r/xmppstanza'

  module ::Jabber
    class JID
      alias :orig_cmp :"<=>"
      def <=>(o)
        return nil unless o.kind_of?(::Jabber::JID)
        orig_cmp(o)
      end
    end
    class Presence < XMPPStanza
      alias :orig_cmp :"<=>"
      def <=>(o)
        return nil unless o.kind_of?(::Jabber::Presence)
        orig_cmp(o)
      end
    end
  end
end