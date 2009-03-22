require File.join(File.dirname(__FILE__), '..', 'notifier')

describe "running the notifier" do 
 
  before(:each) do 
  end
 
  it "should set up a logger instance on init" do 
    n = NotifierCLI.new
    n.log.should_not be_nil
  end
  
  it "should setup loggers" do 
    n = NotifierCLI.new
    n.setup_loggers
    n.log.outputters.size.should > 0
  end
  
  it "should setup recipients with a default file" do 
    n = NotifierCLI.new
    n.setup_recipients
    n.recipients.size.should > 0
  end

  it "should setup recipients with a specified file" do 
    n = NotifierCLI.new
    n.setup_recipients(:filename => File.join(File.dirname(__FILE__), 'fixtures', 'recipients.yaml'))
    n.recipients.size.should > 0
  end
  
  it "should setup recipients with a passed in yaml fragment" do 
    n = NotifierCLI.new
    yaml = File.join(File.dirname(__FILE__), 'fixtures', 'recipients.yaml')
    n.setup_recipients(:yaml => yaml)
    n.recipients.size.should > 0
  end
  
  it "should create an accessor object for every recipient" do 
    n = NotifierCLI.new
    n.setup_recipients
    n.recipients.each do |r|
      r.email.should =~ /@/
      r.name.should =~ /\w+/
      r.phone.should =~ /\d+/
      r.pager.should =~ /\d+/
      r.jid.should =~ /@/
    end
  end

end


def puts(*args) ; end
