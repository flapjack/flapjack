require File.join(File.dirname(__FILE__), '..', 'lib', 'flapjack', 'cli', 'notifier')

describe "running the worker" do 
 
  before(:each) do 
  end
 
  it "should setup a notifier" do 
    n = Flapjack::NotifierCLI.new
    n.notifier = Notifier.new(:logger => n.log, 
                              :recipients => n.recipients)
    n.notifier.should_not be_nil
  end
  
  it "should setup a results queue" do 
    n = Flapjack::NotifierCLI.new
    beanstalk = mock("Beanstalk::Pool")
    beanstalk.stub!(:stats).and_return("blah")
    n.results_queue = beanstalk
    n.results_queue.should_not be_nil
    n.results_queue.stats.class.should == String
  end

  it "should process results" do 
    n = Flapjack::NotifierCLI.new
    n.notifier = Notifier.new(:logger => n.log, 
                              :recipients => n.recipients)
    
    beanstalk = mock("Beanstalk::Pool")
    beanstalk.stub!(:reserve).and_return {
      job = mock("Beanstalk::Job")
      job.should_receive(:body).and_return("--- \n:output: \"\"\n:id: 9\n:retval: 2\n")
      job.should_receive(:delete)
      job
    }
    
    n.results_queue = beanstalk
    n.process_result

  end

end


def puts(*args) ; end
