require File.join(File.dirname(__FILE__), '..', 'notifier')
require File.join(File.dirname(__FILE__), 'helpers')

describe "running the notifier" do 
 
  before(:each) do 
  end
 
  it "should complain if no logger has been specified" do 
    lambda {
      n = Notifier.new
    }.should raise_error(RuntimeError)
  end
  
  it "should have a blank recipients list if none specified" do 
    n = Notifier.new(:logger => MockLogger.new)
    n.recipients.should_not be_nil
    n.recipients.size.should == 0
  end

  it "should warn if no notifiers have been specified" do 
    n = Notifier.new(:logger => MockLogger.new)
    n.log.messages.last.should =~ /no notifiers/
  end

end


def puts(*args) ; end
