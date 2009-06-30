require File.join(File.dirname(__FILE__), '..', 'lib', 'flapjack', 'cli', 'notifier')
require File.join(File.dirname(__FILE__), '..', 'lib', 'flapjack', 'notifier')
require File.join(File.dirname(__FILE__), '..', 'lib', 'flapjack', 'result')
require File.join(File.dirname(__FILE__), 'helpers')

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
    check = Check.new(:id => 9, :status => 0, :command => 'foo', :name => 'foo')
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
    check.status.should == 2
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

end


def puts(*args) ; end
