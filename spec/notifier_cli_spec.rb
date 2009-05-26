require File.join(File.dirname(__FILE__), '..', 'lib', 'flapjack', 'cli', 'notifier')

describe "running the notifier" do 
 
  before(:each) do 
  end
 
  it "should set up a logger instance on init" do 
    n = Flapjack::NotifierCLI.new
    n.log.should_not be_nil
  end
  
  it "should setup loggers" do 
    n = Flapjack::NotifierCLI.new
    n.setup_loggers
    n.log.outputters.size.should > 0
  end
  
  it "should setup recipients with a default file" do 
    n = Flapjack::NotifierCLI.new
    n.setup_recipients
    n.recipients.size.should > 0
  end

  it "should setup recipients with a specified file" do 
    n = Flapjack::NotifierCLI.new
    n.setup_recipients(:filename => File.join(File.dirname(__FILE__), 'fixtures', 'recipients.yaml'))
    n.recipients.size.should > 0
  end
  
  it "should setup recipients with a passed in yaml fragment" do 
    n = Flapjack::NotifierCLI.new
    yaml = File.join(File.dirname(__FILE__), 'fixtures', 'recipients.yaml')
    n.setup_recipients(:yaml => yaml)
    n.recipients.size.should > 0
  end
  
  it "should create an accessor object for every recipient" do 
    n = Flapjack::NotifierCLI.new
    n.setup_recipients
    n.recipients.each do |r|
      r.email.should =~ /@/
      r.name.should =~ /\w+/
      r.phone.should =~ /\d+/
      r.pager.should =~ /\d+/
      r.jid.should =~ /@/
    end
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
