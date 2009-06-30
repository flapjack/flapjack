require File.join(File.dirname(__FILE__), '..', 'lib', 'flapjack', 'cli', 'notifier')

describe Flapjack::NotifierOptions do 
 
  before(:each) do 
  end
 
  # beanstalk
  it "should accept the location of a beanstalk queue in short form" do 
    args = %w(-b localhost -r spec/recipients.yaml -c spec/flapjack-notifier.yaml)
    options = Flapjack::NotifierOptions.parse(args)
    options.host.should == "localhost"
  end
  
  it "should accept the location of a beanstalk queue in long form" do 
    args = %w(--beanstalk localhost -r spec/recipients.yaml -c spec/flapjack-notifier.yaml)
    options = Flapjack::NotifierOptions.parse(args)
    options.host.should == "localhost"
  end

  it "should set a default beanstalk host" do 
    args = %w(-r spec/recipients.yaml -c spec/flapjack-notifier.yaml)
    options = Flapjack::NotifierOptions.parse(args)
    options.host.should == 'localhost'
  end

  # beanstalk port
  it "should accept a specified beanstalk port in short form" do 
    args = %w(-b localhost -p 11340 -r spec/recipients.yaml -c spec/flapjack-notifier.yaml)
    options = Flapjack::NotifierOptions.parse(args)
    options.port.should == 11340
  end
  
  it "should accept a specified beanstalk port in long form" do 
    args = %w(-b localhost --port 11399 -r spec/recipients.yaml -c spec/flapjack-notifier.yaml)
    options = Flapjack::NotifierOptions.parse(args)
    options.port.should == 11399
  end

  it "should set a default beanstalk port" do 
    args = %w(-b localhost -r spec/recipients.yaml -c spec/flapjack-notifier.yaml)
    options = Flapjack::NotifierOptions.parse(args)
    options.port.should == 11300
  end

  # recipients
  it "should accept the location of a recipients file in short form" do 
    args = %w(-b localhost -r spec/recipients.yaml -c spec/flapjack-notifier.yaml)
    options = Flapjack::NotifierOptions.parse(args)
    options.recipients.should == "spec/recipients.yaml"
  end
  
  it "should accept the location of a recipients file in long form" do 
    args = %w(-b localhost --recipient spec/recipients.yaml -c spec/flapjack-notifier.yaml)
    options = Flapjack::NotifierOptions.parse(args)
    options.recipients.should == "spec/recipients.yaml"
  end

  it "should exit if the recipients file doesn't exist" do 
    args = %w(-b localhost -r spec/wangity.yaml -c spec/flapjack-notifier.yaml)
    lambda { 
      Flapjack::NotifierOptions.parse(args) 
    }.should raise_error(SystemExit)
  end

  it "should exit if the recipients file isn't specified" do 
    args = %w(-b localhost -c spec/flapjack-notifier.yaml)
    lambda { 
      Flapjack::NotifierOptions.parse(args) 
    }.should raise_error(SystemExit)
  end

  # config 
  it "should accept the location of a config file in short form" do 
    args = %w(-b localhost -r spec/recipients.yaml -c spec/flapjack-notifier.yaml)
    options = Flapjack::NotifierOptions.parse(args)
    options.config_filename.should == "spec/flapjack-notifier.yaml"
  end

  it "should accept the location of a config file in long form" do 
    args = %w(-b localhost -r spec/recipients.yaml --config spec/flapjack-notifier.yaml)
    options = Flapjack::NotifierOptions.parse(args)
    options.config_filename.should == "spec/flapjack-notifier.yaml"
  end

  it "should provide a default config file if not specified" do 
    args = %w(-b localhost -r spec/recipients.yaml -c spec/flapjack-notifier.yaml)
    options = Flapjack::NotifierOptions.parse(args)
    options.config_filename.should_not be_nil
  end

  it "should exit if the config file doesn't exist" do 
    args = %w(-b localhost --config spec/wangity.yaml)
    lambda { 
      Flapjack::NotifierOptions.parse(args) 
    }.should raise_error(SystemExit)
  end

  # general
  it "should exit on when asked for help in short form" do 
    args = %w(-h)
    lambda { 
      Flapjack::NotifierOptions.parse(args) 
    }.should raise_error(SystemExit)
  end

  it "should exit on when asked for help in long form" do 
    args = %w(--help)
    lambda { 
      Flapjack::NotifierOptions.parse(args) 
    }.should raise_error(SystemExit)
  end
end


def puts(*args) ; end
