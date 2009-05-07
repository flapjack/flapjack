require File.join(File.dirname(__FILE__), '..', 'notifier')

describe NotifierOptions do 
 
  before(:each) do 
  end
 
  # beanstalk
  it "should accept the location of a beanstalk queue in short form" do 
    args = %w(-b localhost)
    options = NotifierOptions.parse(args)
    options.host.should == "localhost"
  end
  
  it "should accept the location of a beanstalk queue in long form" do 
    args = %w(--beanstalk localhost)
    options = NotifierOptions.parse(args)
    options.host.should == "localhost"
  end

  # recipients
  it "should accept the location of a recipients file in short form" do 
    args = %w(-b localhost -r recipients.yaml)
    options = NotifierOptions.parse(args)
    options.recipients.should == "recipients.yaml"
  end
  
  it "should accept the location of a recipients file in long form" do 
    args = %w(-b localhost --recipient recipients.yaml)
    options = NotifierOptions.parse(args)
    options.recipients.should == "recipients.yaml"
  end

  it "should exit if the recipients file doesn't exist" do 
    args = %w(-b localhost --recipient recipients.yaml)
    lambda { 
      NotifierOptions.parse(args) 
    }.should raise_error(SystemExit)
  end

  # general
  it "should exit on when asked for help in short form" do 
    args = %w(-h)
    lambda { 
      NotifierOptions.parse(args) 
    }.should raise_error(SystemExit)
  end

  it "should exit on when asked for help in long form" do 
    args = %w(--help)
    lambda { 
      NotifierOptions.parse(args) 
    }.should raise_error(SystemExit)
  end
end


def puts(*args) ; end
