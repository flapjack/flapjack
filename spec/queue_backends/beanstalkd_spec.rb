require File.join(File.dirname(__FILE__), '..', '..', 'lib', 'flapjack', 'applications', 'notifier')
require File.join(File.dirname(__FILE__), '..', 'helpers')
require 'beanstalk-client'

describe "notifier application" do 

  before(:each) do
    lambda {
      begin
        @beanstalk = Beanstalk::Connection.new('localhost:11300', 'results')
      rescue => e
        # give helpful error messages to people unfamiliar with the test suite
        puts "You need to have an instance of beanstalkd running locally to run these tests!"
        raise
      end
    }.should_not raise_error
  end

  it "should load a good test result" do 
    @beanstalk.yput({:output => "", :id => 9, :retval => 0})

    options = { :notifiers => {},
                :logger => MockLogger.new,
                :queue_backend => {:type => :beanstalkd} }
    app = Flapjack::Notifier::Application.run(options)
    lambda {
      app.process_result
    }.should_not raise_error
  end

end

