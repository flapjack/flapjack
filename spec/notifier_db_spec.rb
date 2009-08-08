#!/usr/bin/env ruby

__DIR__ = File.dirname(__FILE__)
basedir = File.join(__DIR__, '..')

require File.join(basedir, 'lib', 'flapjack', 'cli', 'notifier')
require File.join(basedir, 'lib', 'flapjack', 'notifier')
require File.join(basedir, 'lib', 'flapjack', 'result')
require File.join(__DIR__, 'helpers')

GOOD = 0
BAD  = 1
UGLY = 2

describe "giving feedback to flapjack-admin" do 

  it "should setup a database connection as specified in the config file" do 
    n = Flapjack::NotifierCLI.new(:logger => MockLogger.new)
    n.setup_config(:yaml => {:database_uri => "sqlite3://#{File.expand_path(File.dirname(__FILE__))}/test.db"})
    n.setup_database
    lambda {
      DataMapper.repository(:default).adapter
    }.should_not raise_error(ArgumentError)
  end

  it "should setup a database connection by a uri" do 
    n = Flapjack::NotifierCLI.new(:logger => MockLogger.new)
    n.setup_database(:database_uri => "sqlite3://#{File.expand_path(File.dirname(__FILE__))}/test.db")
    lambda {
      DataMapper.repository(:default).adapter
    }.should_not raise_error(ArgumentError)
  end

  it "should update a check in the checks database" do 
    # setup the notifier
    n = Flapjack::NotifierCLI.new(:logger => MockLogger.new)
    n.setup_config(:yaml => {:notifiers => {}})
    n.setup_recipients(:filename => File.join(File.dirname(__FILE__), 'fixtures', 'recipients.yaml'))
    n.setup_database(:database_uri => "sqlite3://#{File.expand_path(File.dirname(__FILE__))}/test.db")
    n.setup_notifier
    
    # create a dummy check
    DataMapper.auto_migrate!
    check = Check.new(:id => 9, :status => GOOD, :command => 'foo', :name => 'foo')
    check.save.should be_true

    # mock out the beanstalk
    beanstalk = mock("Beanstalk::Pool")
    beanstalk.stub!(:reserve).and_return {
      job = mock("Beanstalk::Job")
      job.should_receive(:body).and_return("--- \n:output: \"\"\n:id: 9\n:retval: 2\n")
      job.should_receive(:delete)
      job
    }
    
    n.results_queue = beanstalk
    n.process_result

    # has the check been updated?
    check = Check.get(9)
    check.status.should == UGLY
  end

  it "should explode if no database uri is specified" do
    n = Flapjack::NotifierCLI.new(:logger => MockLogger.new)
    n.setup_config(:yaml => {})
    lambda {
      n.setup_database
    }.should raise_error(ArgumentError)
  end

  it "should log an error if the check id for a check doesn't exist in the db" do 
    # setup the notifier
    n = Flapjack::NotifierCLI.new(:logger => MockLogger.new)
    n.setup_config(:yaml => {:notifiers => {}})
    n.setup_recipients(:filename => File.join(File.dirname(__FILE__), 'fixtures', 'recipients.yaml'))
    n.setup_database(:database_uri => "sqlite3://#{File.expand_path(File.dirname(__FILE__))}/test.db")
    n.setup_notifier
    
    # create a dummy check
    DataMapper.auto_migrate!

    # mock out the beanstalk
    beanstalk = mock("Beanstalk::Pool")
    beanstalk.stub!(:reserve).and_return {
      job = mock("Beanstalk::Job")
      job.should_receive(:body).and_return("--- \n:output: \"\"\n:id: 9\n:retval: 2\n")
      job.should_receive(:delete)
      job
    }
    
    n.results_queue = beanstalk
    n.process_result

    n.log.messages.find {|msg| msg =~ /check 9.+doesn't exist/i}.should_not be_nil
  end

  it "should raise a warning if the specified database doesn't have structure" do
    n = Flapjack::NotifierCLI.new(:logger => MockLogger.new)
    n.setup_database(:database_uri => "sqlite3:///tmp/flapjack_unstructured.db")

    n.log.messages.find {|msg| msg =~ /doesn't .+ any structure/}.should_not be_nil
  end

  it "should notify on a check if parent is clear" do 
    # setup the notifier
    n = Flapjack::NotifierCLI.new(:logger => MockLogger.new)
    n.setup_config(:yaml => {:notifiers => {}})
    n.setup_recipients(:filename => File.join(File.dirname(__FILE__), 'fixtures', 'recipients.yaml'))
    n.setup_database(:database_uri => "sqlite3://#{File.expand_path(File.dirname(__FILE__))}/test.db")
    
    # create a dummy check
    DataMapper.auto_migrate!
    child_check = Check.new(:id => 3, :status => GOOD, :command => 'foo', :name => 'foo')
    child_check.save.should be_true

    parent_check = Check.new(:id => 17, :status => GOOD, :command => 'bar', :name => 'bar')
    parent_check.save.should be_true

    relation = RelatedCheck.new(:parent_check => parent_check, :child_check => child_check)
    relation.save.should be_true

    # mock out notifier
    mock_notifier = mock("Flapjack::Notifier")
    mock_notifier.should_receive(:notify!)
    n.notifier = mock_notifier

    # mock out the beanstalk
    beanstalk = mock("Beanstalk::Pool")
    beanstalk.stub!(:reserve).and_return {
      job = mock("Beanstalk::Job")
      job.should_receive(:body).and_return("--- \n:output: \"\"\n:id: 3\n:retval: 2\n")
      job.should_receive(:delete)
      job
    }
    
    n.results_queue = beanstalk
    n.process_result

    n.log.messages.find {|msg| msg =~ /not notifying.+6.+/i}.should be_nil
  end

  it "should not notify on a check if parent is failing" do 
    # setup the notifier
    n = Flapjack::NotifierCLI.new(:logger => MockLogger.new)
    n.setup_config(:yaml => {:notifiers => {}})
    n.setup_recipients(:filename => File.join(File.dirname(__FILE__), 'fixtures', 'recipients.yaml'))
    n.setup_database(:database_uri => "sqlite3://#{File.expand_path(File.dirname(__FILE__))}/test.db")
    #n.setup_notifier
    
    # create a dummy check
    DataMapper.auto_migrate!
    child_check = Check.new(:id => 6, :status => GOOD, :command => 'foo', :name => 'foo')
    child_check.save.should be_true

    parent_check = Check.new(:id => 22, :status => UGLY, :command => 'bar', :name => 'bar')
    parent_check.save.should be_true

    relation = RelatedCheck.new(:parent_check => parent_check, :child_check => child_check)
    relation.save.should be_true

    # mock out notifier
    mock_notifier = mock("Flapjack::Notifier")
    mock_notifier.should_not_receive(:notify!)
    n.notifier = mock_notifier

    # mock out the beanstalk
    beanstalk = mock("Beanstalk::Pool")
    beanstalk.stub!(:reserve).and_return {
      job = mock("Beanstalk::Job")
      job.should_receive(:body).and_return("--- \n:output: \"\"\n:id: 6\n:retval: 2\n")
      job.should_receive(:delete)
      job
    }
    
    n.results_queue = beanstalk
    n.process_result

    n.log.messages.find {|msg| msg =~ /not notifying.+6.+/i}.should_not be_nil
  end

  it "should create events for failing checks" do 
    # setup the notifier
    n = Flapjack::NotifierCLI.new(:logger => MockLogger.new)
    n.setup_config(:yaml => {:notifiers => {}})
    n.setup_recipients(:filename => File.join(File.dirname(__FILE__), 'fixtures', 'recipients.yaml'))
    n.setup_database(:database_uri => "sqlite3://#{File.expand_path(File.dirname(__FILE__))}/test.db")
    
    # create a dummy check
    DataMapper.auto_migrate!
    check = Check.new(:id => 29, :status => GOOD, :command => 'foo', :name => 'foo')
    check.save.should be_true

    number_of_existing_events = check.events.size

    # mock out notifier
    mock_notifier = mock("Flapjack::Notifier")
    mock_notifier.should_receive(:notify!)
    n.notifier = mock_notifier

    # mock out the beanstalk
    beanstalk = mock("Beanstalk::Pool")
    beanstalk.stub!(:reserve).and_return {
      job = mock("Beanstalk::Job")
      job.should_receive(:body).and_return("--- \n:output: \"\"\n:id: 29\n:retval: 2\n")
      job.should_receive(:delete)
      job
    }
    
    n.results_queue = beanstalk
    n.process_result

    n.log.messages.find {|msg| msg =~ /creating event for .+29.+/i}.should_not be_nil

    # there should be 1 new event
    check.events.size.should == number_of_existing_events + 1
  end

end


def puts(*args) ; end
