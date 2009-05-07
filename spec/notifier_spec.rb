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

  it "should log when adding a new notifier" do
    mock_notifier = mock("MockNotifier")
    n = Notifier.new(:logger => MockLogger.new, 
                     :notifiers => [mock_notifier])
    n.log.messages.last.should =~ /using the (.+) notifier/
  end

  it "should call notify on each notifier when notifying" do 
    mock_notifier = mock("MockNotifier")
    mock_notifier.should_receive(:notify)

    n = Notifier.new(:logger => MockLogger.new, 
                     :notifiers => [mock_notifier],
                     :recipients => [OpenStruct.new({:name => "John Doe"})])
    n.notify!(Result.new(:id => 'mock result'))
  end

  it "should log notification on each notifier" do 
    mock_notifier = mock("MockNotifier")
    mock_notifier.stub!(:notify)

    n = Notifier.new(:logger => MockLogger.new, 
                     :notifiers => [mock_notifier],
                     :recipients => [OpenStruct.new({:name => "John Doe"})])
    n.notify!(Result.new(:id => '12345'))
    n.log.messages.last.should =~ /12345/
    n.log.messages.last.should =~ /John Doe/
  end
end


def puts(*args) ; end
