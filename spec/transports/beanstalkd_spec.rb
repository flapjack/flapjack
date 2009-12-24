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
        puts
        puts "You need to have an instance of beanstalkd running locally to run these tests!"
        puts
        raise
      end
    }.should_not raise_error
  end

  it "should handle good, bad, and ugly test result" do 
    [ {:output => "", :id => 1, :retval => 0},
      {:output => "", :id => 2, :retval => 1},
      {:output => "", :id => 3, :retval => 2} ].each do |result|
      @beanstalk.yput(result)
    end

    options = { :notifiers => {},
                :filters => [],
                :log => MockLogger.new,
                :transport => {:backend => :beanstalkd},
                :persistence => {:backend => :mock_persistence_backend,                                                                    
                                   :basedir => File.join(File.dirname(__FILE__), '..', 'persistence')}} 
    app = Flapjack::Notifier::Application.run(options)

    3.times do |n|
      lambda {
        app.process_result
      }.should_not raise_error
    end
  end

end

