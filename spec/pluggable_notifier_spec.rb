require File.join(File.dirname(__FILE__), '..', 'lib', 'flapjack', 'applications', 'notifier')
require File.join(File.dirname(__FILE__), 'helpers')

describe "notifier application" do 

  # 
  # booting interface
  #

  it "should have a simple interface to start the notifier" do 
    options = { :notifiers => {},
                :log => MockLogger.new,
                :check_backend => {:type => :mockbackend, 
                                   :basedir => File.join(File.dirname(__FILE__), 'check_backends')} }
    app = Flapjack::Notifier::Application.run(options)
  end

  it "should log when loading a notifier" do 
    options = { :notifiers => {:testmailer => {}}, 
                :log => MockLogger.new,
                :notifier_directories => [File.join(File.dirname(__FILE__),'notifier-directories', 'spoons')],
                :check_backend => {:type => :mockbackend, 
                                   :basedir => File.join(File.dirname(__FILE__), 'check_backends')} }
    app = Flapjack::Notifier::Application.run(options)
    app.log.messages.find {|msg| msg =~ /loading the testmailer notifier/i}.should_not be_nil
  end

  it "should warn if a specified notifier doesn't exist" do 
    options = { :notifiers => {:nonexistant => {}}, 
                :log => MockLogger.new,
                :check_backend => {:type => :mockbackend, 
                                   :basedir => File.join(File.dirname(__FILE__), 'check_backends')} }
    app = Flapjack::Notifier::Application.run(options)
    app.log.messages.find {|msg| msg =~ /Flapjack::Notifiers::Nonexistant doesn't exist/}.should_not be_nil
  end

  it "should give precedence to notifiers in user-specified notifier directories" do 
    options = { :notifiers => {:testmailer => {}}, 
                :log => MockLogger.new,
                :notifier_directories => [File.join(File.dirname(__FILE__),'notifier-directories', 'spoons')],
                :check_backend => {:type => :mockbackend, 
                                   :basedir => File.join(File.dirname(__FILE__), 'check_backends')} }
    app = Flapjack::Notifier::Application.run(options)
    app.log.messages.find {|msg| msg =~ /spoons/i}.should_not be_nil
    # this will raise an exception if the notifier directory isn't specified,
    # as the mailer notifier requires several arguments anyhow
  end

  it "should pass global notifier config options to each notifier"

  it "should merge recipients from a file and a specified list of recipients" do
    options = { :notifiers => {},
                :log => MockLogger.new,
                :recipients => {:filename => File.join(File.dirname(__FILE__), 'fixtures', 'recipients.yaml'),
                                :list => [{:name => "Spoons McDoom"}]},
                :check_backend => {:type => :mockbackend, 
                                   :basedir => File.join(File.dirname(__FILE__), 'check_backends')} }
    app = Flapjack::Notifier::Application.run(options)
    app.log.messages.find {|msg| msg =~ /fixtures\/recipients\.yaml/i}.should_not be_nil
    # should have one specified in options[:recipients][:list], and some from specified recipients.yaml
    app.recipients.size.should > 1
  end

  #
  # queues
  #

  it "should load a beanstalkd as the default queue backend" do 
    options = { :notifiers => {}, 
                :log => MockLogger.new,
                :check_backend => {:type => :mockbackend, 
                                   :basedir => File.join(File.dirname(__FILE__), 'check_backends')} }
    app = Flapjack::Notifier::Application.run(options)
    app.log.messages.find {|msg| msg =~ /loading.+beanstalkd.+backend/i}.should_not be_nil
  end

  it "should load a queue backend as specified in options" do 
    options = { :notifiers => {},
                :log => MockLogger.new,
                :queue_backend => {:type => :beanstalkd},
                :check_backend => {:type => :mockbackend, 
                                   :basedir => File.join(File.dirname(__FILE__), 'check_backends')} }
    app = Flapjack::Notifier::Application.run(options)
    app.log.messages.find {|msg| msg =~ /loading.+beanstalkd.+backend/i}.should_not be_nil
  end

  it "should raise if the specified queue backend doesn't exist" do
    options = { :notifiers => {}, 
                :log => MockLogger.new,
                :queue_backend => {:type => :nonexistant} }
    lambda {
      app = Flapjack::Notifier::Application.run(options)
      #app.log.messages.find {|msg| msg =~ /attempted to load nonexistant/i}.should_not be_nil
    }.should raise_error
  end

  it "should use a limited interface for dealing with the results queue" do
    
    # Interface for a Flapjack::Transport::<backend> is as follows: 
    # 
    #  methods: next, delete
    #

    options = { :notifiers => {}, 
                :log => MockLogger.new,
                :queue_backend => {:type => :mockbackend, 
                                   :basedir => File.join(File.dirname(__FILE__), 'transports')},
                :check_backend => {:type => :mockbackend, 
                                   :basedir => File.join(File.dirname(__FILE__), 'check_backends')} }
    app = Flapjack::Notifier::Application.run(options)

    # processes a single result
    app.process_result

    # check that allowed methods were called
    allowed_methods = %w(next delete)
    allowed_methods.each do |method|
      app.log.messages.find {|msg| msg =~ /#{method.gsub(/\?/,'\?')} was called on Mockbackend/i}.should_not be_nil
    end

    # check that no other methods were
    called_methods = app.log.messages.find_all {|msg| msg =~ /^method .+ was called on Mockbackend$/i }.map {|msg| msg.split(' ')[1]}
    (allowed_methods - called_methods).size.should == 0
  end

  it "should use a limited interface for dealing with results off the results queue" do

    # Interface for a Flapjack::Transport::Result is as follows: 
    # 
    #  methods: id, warning?, critical?
    #

    options = { :notifiers => {}, 
                :log => MockLogger.new,
                :queue_backend => {:type => :mockbackend, 
                                   :basedir => File.join(File.dirname(__FILE__), 'transports')},
                :check_backend => {:type => :mockbackend, 
                                   :basedir => File.join(File.dirname(__FILE__), 'check_backends')} }
    app = Flapjack::Notifier::Application.run(options)

    # processes a single result
    app.process_result

    # check that allowed methods were called
    allowed_methods = %w(id warning?)
    allowed_methods.each do |method|
      app.log.messages.find {|msg| msg =~ /#{method.gsub(/\?/,'\?')} was called/i}.should_not be_nil
    end

    # check that no other methods were called
    called_methods = app.log.messages.find_all {|msg| msg =~ /^method .+ was called on Result$/i }.map {|msg| msg.split(' ')[1]}.uniq
    (allowed_methods - called_methods).size.should == 0
  end

  it "should use a limited interface for dealing with the check backend" do
    
    # Interface for a Flapjack::CheckBackends::<backend> is as follows: 
    # 
    #  methods: any_parents_failed?, save
    #

    options = { :notifiers => {}, 
                :log => MockLogger.new,
                :queue_backend => {:type => :mockbackend, 
                                   :basedir => File.join(File.dirname(__FILE__), 'transports')},
                :check_backend => {:type => :mockbackend, 
                                   :basedir => File.join(File.dirname(__FILE__), 'check_backends')} }
    app = Flapjack::Notifier::Application.run(options)

    # processes a single result
    app.process_result

    # check that allowed methods were called
    allowed_methods = %w(any_parents_failed? save)
    allowed_methods.each do |method|
      app.log.messages.find {|msg| msg =~ /#{method.gsub(/\?/,'\?')} was called/i}.should_not be_nil
    end

    # check that no other methods were called
    called_methods = app.log.messages.find_all {|msg| msg =~ /^method .+ was called on CheckBackends::Mockbackend$/i }.map {|msg| msg.split(' ')[1]}
    (allowed_methods - called_methods).size.should == 0
  end


  #
  # check backends
  #

  it "should load couchdb as the default check backend"

  it "should load a check backend as specified in options" do 
    options = { :notifiers => {},
                :log => MockLogger.new,
                :check_backend => {:type => :mockbackend, 
                                   :basedir => File.join(File.dirname(__FILE__), 'check_backends')} }
    app = Flapjack::Notifier::Application.run(options)
    app.log.messages.find {|msg| msg =~ /loading.+mockbackend.+backend/i}.should_not be_nil
  end

  it "should raise if the specified check backend doesn't exist" do
    options = { :notifiers => {}, 
                :log => MockLogger.new,
                :check_backend => {:type => :nonexistant} }
    lambda {
      app = Flapjack::Notifier::Application.run(options)
    }.should raise_error(LoadError)
  end

end

def puts(*args) ; end
