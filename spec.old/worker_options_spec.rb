require 'rubygems'
$: << File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib'))
require 'lib/flapjack/cli/worker'

describe Flapjack::WorkerOptions do 
 
  before(:each) do 
  end
 
  # beanstalk
  it "should accept the location of a beanstalk queue in short form" do 
    args = %w(-b localhost)
    options = Flapjack::WorkerOptions.parse(args)
    options.host.should == "localhost"
  end
  
  it "should accept the location of a beanstalk queue in long form" do 
    args = %w(--beanstalk localhost)
    options = Flapjack::WorkerOptions.parse(args)
    options.host.should == "localhost"
  end

  it "should set a default beanstalk host" do 
    args = []
    options = Flapjack::WorkerOptions.parse(args)
    options.host.should == 'localhost'
  end

  # beanstalk port
  it "should accept a specified beanstalk port in short form" do 
    args = %w(-b localhost -p 11340)
    options = Flapjack::WorkerOptions.parse(args)
    options.port.should == 11340
  end
  
  it "should accept a specified beanstalk port in long form" do 
    args = %w(-b localhost --port 11399)
    options = Flapjack::WorkerOptions.parse(args)
    options.port.should == 11399
  end

  it "should set a default beanstalk port" do 
    args = %w(-b localhost)
    options = Flapjack::WorkerOptions.parse(args)
    options.port.should == 11300
  end

  it "should accept a specified checks directory in short form" do 
    args = %w(-c /tmp)
    options = Flapjack::WorkerOptions.parse(args)
    options.checks_directory.should == "/tmp"
  end

  it "should accept a specified checks directory in long form" do 
    args = %w(--checks-directory /tmp)
    options = Flapjack::WorkerOptions.parse(args)
    options.checks_directory.should == "/tmp"
  end

  it "should set a default checks directory" do 
    args = []
    options = Flapjack::WorkerOptions.parse(args)
    options.checks_directory.should_not be_nil
  end

  # general
  it "should exit on when asked for help in short form" do 
    args = %w(-h)
    lambda { 
      Flapjack::WorkerOptions.parse(args) 
    }.should raise_error(SystemExit)
  end

  it "should exit on when asked for help in long form" do 
    args = %w(--help)
    lambda { 
      Flapjack::WorkerOptions.parse(args) 
    }.should raise_error(SystemExit)
  end
end


def puts(*args) ; end
