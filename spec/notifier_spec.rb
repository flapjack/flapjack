require File.join(File.dirname(__FILE__), '..', 'lib', 'flapjack', 'notifier_engine')
require File.join(File.dirname(__FILE__), '..', 'lib', 'flapjack', 'transports', 'result')
require File.join(File.dirname(__FILE__), 'helpers')

describe "running the notifier" do 
 
  before(:each) do 
  end
 
  it "should complain if no logger has been specified" do 
    lambda {
      n = Flapjack::NotifierEngine.new
    }.should raise_error(RuntimeError)
  end
  
  it "should warn if no notifiers have been specified" do 
    n = Flapjack::NotifierEngine.new(:log => MockLogger.new)
    n.log.messages.last.should =~ /no notifiers/
  end

  it "should log when adding a new notifier" do
    mock_notifier = mock("MockFlapjack::NotifierEngine")
    n = Flapjack::NotifierEngine.new(:log => MockLogger.new, 
                     :notifiers => [mock_notifier])
    n.log.messages.last.should =~ /using the (.+) notifier/
  end

  it "should call notify on each notifier when notifying" do 
    mock_notifier = mock("MockFlapjack::NotifierEngine")
    mock_notifier.should_receive(:notify)

    result = Flapjack::Transport::Result.new(:result => {:check_id => 12345})

    n = Flapjack::NotifierEngine.new(:log => MockLogger.new, 
                                     :notifiers => [mock_notifier])
    n.notify!(:result => result, 
              :event => true, 
              :recipients => [OpenStruct.new({:name => "John Doe"})])
  end

  it "should log notification on each notifier" do 
    mock_notifier = mock("MockFlapjack::NotifierEngine")
    mock_notifier.stub!(:notify)

    result = Flapjack::Transport::Result.new(:result => {:check_id => 12345})

    n = Flapjack::NotifierEngine.new(:log => MockLogger.new, 
                                     :notifiers => [mock_notifier])
    n.notify!(:result => result, 
              :event => true,
              :recipients => [OpenStruct.new({:name => "John Doe"})])
    n.log.messages.last.should =~ /12345/
    n.log.messages.last.should =~ /John Doe/
  end
end


