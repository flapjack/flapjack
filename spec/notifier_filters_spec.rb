require File.join(File.dirname(__FILE__), '..', 'lib', 'flapjack', 'applications', 'notifier')
require File.join(File.dirname(__FILE__), '..', 'lib', 'flapjack', 'transports', 'result')
require File.join(File.dirname(__FILE__), 'helpers')

describe "running the notifier" do 
  
  before(:all) do 
    @options = { :notifiers => {:testmailer => {}},
                 :notifier_directories => [File.join(File.dirname(__FILE__),'notifier-directories', 'spoons')],
                 :recipients => [{:name => "Spoons McDoom"}],
                 :transport => {:backend => :mock_transport, 
                                :basedir => File.join(File.dirname(__FILE__), 'transports')},
                 :persistence => {:backend => :mock_persistence_backend, 
                                  :basedir => File.join(File.dirname(__FILE__), 'persistence')},
                 :filter_directories => [File.join(File.dirname(__FILE__),'test-filters')]
               }
  end

  it "should notify by default" do 
    @options[:filters] = []
    @options[:log] = MockLogger.new

    app = Flapjack::Notifier::Application.run(@options)
    # processes a MockResult, as defined in spec/transports/mock_transport.rb
    app.process_result

    app.log.messages.find {|m| m =~ /testmailer notifying/i}.should be_true
  end

  it "should not notify if any filters fail" do 
    @options[:filters] = ['blocker']
    @options[:log] = MockLogger.new
    
    app = Flapjack::Notifier::Application.run(@options)
    # processes a MockResult, as defined in spec/transports/mock_transport.rb
    app.process_result

    app.log.messages.find {|m| m =~ /testmailer notifying/i}.should be_nil
  end

  it "should notify if all filters pass" do
    @options[:filters] = ['mock']
    @options[:log] = MockLogger.new

    app = Flapjack::Notifier::Application.run(@options)
    # processes a MockResult, as defined in spec/transports/mock_transport.rb
    app.process_result

    app.log.messages.find {|m| m =~ /testmailer notifying/i}.should be_true
  end

end
