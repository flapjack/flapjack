require File.join(File.dirname(__FILE__), '..', '..', 'lib', 'flapjack', 'notifiers', 'xmpp', 'init')
require File.join(File.dirname(__FILE__), '..', 'helpers')

describe "xmpp notifier" do 

  it "should error if no login details provided" do 
    lambda {
      xmpp = Flapjack::Notifiers::Xmpp.new
    }.should raise_error(ArgumentError)
  end

  it "should error if no recipient is provided" do
    xmpp = Flapjack::Notifiers::Xmpp.new(:jid => "5b73a016c5c644e9bf1601a241fc27f5@jabber.org", :password => "5b73a016c5c644e9bf1601a241fc27f5")
    lambda {
      xmpp.notify(:result => 'foo')
    }.should raise_error(ArgumentError, /recipient/)
  end

  it "should error if no result is provided" do
    xmpp = Flapjack::Notifiers::Xmpp.new(:jid => "5b73a016c5c644e9bf1601a241fc27f5@jabber.org", :password => "5b73a016c5c644e9bf1601a241fc27f5")
    lambda {
      xmpp.notify(:who => 'foo')
    }.should raise_error(ArgumentError, /result/)
  end

  it "should deliver message to a recipient" do 
    xmpp = Flapjack::Notifiers::Xmpp.new(:jid => "5b73a016c5c644e9bf1601a241fc27f5@jabber.org", :password => "5b73a016c5c644e9bf1601a241fc27f5")
    lambda {
      response = xmpp.notify(:who => OpenStruct.new(:jid => "5b73a016c5c644e9bf1601a241fc27f5@jabber.org"), 
                             :result => OpenStruct.new(:id => 11, :status => 2, :output => "foo"))
    }.should_not raise_error
  end

end


