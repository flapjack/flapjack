$: << File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib'))
require 'lib/flapjack/cli/worker'
require File.join(File.dirname(__FILE__), 'helpers')

describe "running the worker" do 
 
  before(:each) do 
  end
 
  it "should be able to specify and host and port to connect to" do
    w = Flapjack::Worker.new(:host => 'localhost', 
                             :port => 13401, 
                             :logger => MockLogger.new)
    w.jobs.should_not be_nil
    w.results.should_not be_nil
    # FIXME: probably very brittle
    w.jobs.instance_variable_get("@addrs").should == ['localhost:13401']
    w.results.instance_variable_get("@addrs").should == ['localhost:13401']
  end

  it "should perform a check" do 
    w = Flapjack::Worker.new(:host => 'localhost', 
                             :port => 11300, 
                             :logger => MockLogger.new)
    # if this fails your machine is truly fucked
    output, retval = w.perform_check('echo foo') 
    output.should =~ /foo/
    retval.should == 0
  end

  it "should get a job and produce a check" do 

    w = Flapjack::Worker.new(:host => 'localhost', 
                             :port => 11300, 
                             :logger => MockLogger.new)
   
    # the pool should be touched
    beanstalk = mock("Beanstalk::Pool")
    beanstalk.stub!(:reserve).and_return {
      # and it should produce a job
      job = mock("Beanstalk::Job")
      job.should_receive(:body).and_return("--- \n:command: \"collectd-nagios -s /var/run/collectd-unixsock -H theodor -n cpu-0/cpu-idle -w 30: -c 10:\"\n:frequency: 30\n:id: 4\n")
      job
    }
    w.jobs = beanstalk
    
    # get the check
    job, check = w.get_check

    # verify helper methods
    check.command.should =~ /^collectd-nagios/
    check.id.should == 4
    check.frequency.should == 30
  end

  it "should clean up after itself" do 
    w = Flapjack::Worker.new(:host => 'localhost', 
                             :port => 11300, 
                             :logger => MockLogger.new)

    # a new job should be created for the check
    beanstalk = mock("Beanstalk::Pool")
    beanstalk.should_receive(:yput).with(an_instance_of(Hash), an_instance_of(Fixnum), 30)
    w.jobs = beanstalk

    # the job should be deleted
    job = mock("Beanstalk::Job")
    job.should_receive(:delete)

    # frequency determines when the check is next available to run
    check = mock("Check")
    check.should_receive(:frequency).and_return(30)
    check.should_receive(:to_h).and_return({})

    # do the cleanup
    w.cleanup_job(:job => job, :check => check)
  end

  it "should report the results of the check" do 
    w = Flapjack::Worker.new(:host => 'localhost', 
                             :port => 11300, 
                             :logger => MockLogger.new)

    # we need to put the results on the results beanstalk
    beanstalk = mock("Beanstalk::Pool")
    beanstalk.should_receive(:yput)
    w.results = beanstalk 

    # we need to report the check id
    check = mock("Check")
    check.should_receive(:id).at_least(:once)

    # we need to report the status
    retval = mock("Process::Status")
    retval.should_receive(:to_i).and_return(0)

    # do the reporting
    w.report_check(:result => "foo", :retval => retval, :check => check)
  end

end


def puts(*args) ; end
