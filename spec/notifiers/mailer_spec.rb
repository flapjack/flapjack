require File.join(File.dirname(__FILE__), '..', '..', 'lib', 'flapjack', 'notifiers', 'mailer', 'init')
require File.join(File.dirname(__FILE__), '..', 'helpers')

describe "mailing notifier" do 

#  it "should set a from address" do 
#    mailer = Flapjack::Notifiers::Mailer.new(:from_address => "test@example.org")
#  end

  it "should error if no from address is provided" do 
    lambda {
      mailer = Flapjack::Notifiers::Mailer.new
    }.should raise_error(ArgumentError)
  end

  it "should error if no recipient is provided" do
    mailer = Flapjack::Notifiers::Mailer.new(:from_address => "test@example.org")
    lambda {
      mailer.notify()
    }.should raise_error(ArgumentError, /recipient/)
  end

  it "should error if no result is provided" do
    mailer = Flapjack::Notifiers::Mailer.new(:from_address => "test@example.org")
    lambda {
      mailer.notify(:who => 'foo')
    }.should raise_error(ArgumentError, /result/)
  end

  it "should deliver mail to a recipient" do 
    mailer = Flapjack::Notifiers::Mailer.new(:from_address => "test@example.org")
    response = mailer.notify(:who => OpenStruct.new(:email => "nobody@example.org"), 
                             :result => OpenStruct.new(:id => 11, :status => 2, :output => "foo"))
    response.status.should == '250'
  end

  it "should have a configurable server to send through"
end


