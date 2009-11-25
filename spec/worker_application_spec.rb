require File.join(File.dirname(__FILE__), '..', 'lib', 'flapjack', 'applications', 'worker')
require File.join(File.dirname(__FILE__), 'helpers')

describe "worker application" do 

  it "should have a simple booting interface " do 
    options = {:log => MockLogger.new}
    app = Flapjack::Worker::Application.run(options)
  end

  it "should load beanstalkd as the default transport" do 
    options = {:log => MockLogger.new}
    app = Flapjack::Worker::Application.run(options)

    app.log.messages.find {|msg| msg =~ /loading.+beanstalkd.+transport/i}.should_not be_nil
  end

  it "should setup two transports (checks + results)" do 
    options = {:log => MockLogger.new}
    app = Flapjack::Worker::Application.run(options)

    app.log.messages.find_all {|msg| msg =~ /loading.+beanstalkd.+transport/i}.size.should == 2
  end

  it "should load a transport as specified in options" do 
    options = {:log => MockLogger.new, :transport => {:type => :beanstalkd}}
    app = Flapjack::Worker::Application.run(options)

    app.log.messages.find {|msg| msg =~ /loading.+beanstalkd.+transport/i}.should_not be_nil
  end

  it "should error if the specified transport dosen't exist" do 
    options = {:log => MockLogger.new, :transport => {:type => :nonexistant}}
    lambda {
      app = Flapjack::Worker::Application.run(options)
    }.should raise_error
  end

  it "should execute checks in a sandbox"

  it "should use a limited interface for dealing with transports" do 
    options = { :log => MockLogger.new, 
                :transport => {:type => :mock_transport, 
                               :basedir => File.join(File.dirname(__FILE__), 'transports')} }
    app = Flapjack::Worker::Application.run(options)
    app.process_check

    # check allowed methods were called
    allowed_methods = %w(next)
    allowed_methods.each do |method|
      app.log.messages.find {|msg| msg =~ /#{method} was called/}.should_not be_nil 
    end

    # check no other methods were called
    called_methods = app.log.messages.find_all {|msg| msg =~ /^method .+ was called on MockTransport$/i }.map {|msg| msg.split(' ')[1]}
    (allowed_methods - called_methods).size.should == 0
  end


end
