require 'spec_helper'

require 'flapjack/gateways/pagerduty'

describe Flapjack::Gateways::Pagerduty, :logger => true do

  let(:config) { {'queue'    => 'pagerduty_notifications'} }

  let(:now)   { Time.new }

  let(:redis) {  mock('redis') }

  context 'notifications' do

    let(:message) { {'notification_type'  => 'problem',
                     'contact_first_name' => 'John',
                     'contact_last_name' => 'Smith',
                     'address' => 'pdservicekey',
                     'state' => 'CRITICAL',
                     'summary' => '',
                     'last_state' => 'OK',
                     'last_summary' => 'TEST',
                     'details' => 'Testing',
                     'time' => now.to_i,
                     'event_id' => 'app-02:ping'} 
                  }

    # TODO use separate threads in the test instead?
    it "starts and is stopped by an exception" do
      Redis.should_receive(:new).and_return(redis)

      Kernel.should_receive(:sleep).with(10)

      Flapjack::Data::Message.should_receive(:foreach_on_queue).
        with('pagerduty_notifications', :redis => redis).and_yield(message)

      Flapjack::Data::Message.should_receive(:wait_for_queue).
        with('pagerduty_notifications', :redis => redis).and_raise(Flapjack::PikeletStop)

      fpn = Flapjack::Gateways::Pagerduty::Notifier.new(:config => config, :logger => @logger)      
      fpn.should_receive(:handle_message).with(message)
      fpn.should_receive(:test_pagerduty_connection).twice.and_return(false, true)
      fpn.start
    end

    it "tests the pagerduty connection" do
      fpn = Flapjack::Gateways::Pagerduty::Notifier.new(:config => config, :logger => @logger)      

      stub_request(:post, "https://events.pagerduty.com/generic/2010-04-15/create_event.json").
         with(:body => {'service_key'  => '11111111111111111111111111111111',
                        'incident_key' => 'Flapjack is running a NOOP',
                        'event_type'   => 'nop',
                        'description'  => 'I love APIs with noops.'}.to_json).
         to_return(:status => 200, :body => {'status' => 'success'}.to_json)

      fpn.send(:test_pagerduty_connection)
    end

    it "handles notifications received via Redis" do
      fpn = Flapjack::Gateways::Pagerduty::Notifier.new(:config => config, :logger => @logger)      

      stub_request(:post, "https://events.pagerduty.com/generic/2010-04-15/create_event.json").
         with(:body => {'service_key'  => 'pdservicekey',
                        'incident_key' => 'app-02:ping',
                        'event_type'   => 'trigger',
                        'description'  => 'PROBLEM - "ping" on app-02 is CRITICAL - '}.to_json).
         to_return(:status => 200, :body => {'status' => 'success'}.to_json)

      fpn.send(:handle_message, message)
    end

  end

  context 'acknowledgements' do

    # TODO use separate threads in the test instead?
    it "starts and is stopped by an exception"

    it "doesn't look for acknowledgements if this search is already running"

    it "looks for acknowledgements if the search is not already running"

    # Testing the private PagerDuty methods separately, it's simpler. May be
    # an argument for splitting some of them to another module, accessed by this
  # class, in which case it makes more sense for the methods to be public.

    it "looks for acknowledgements via the PagerDuty API"

    it "creates acknowledgements when pagerduty acknowledgements are found"

    it "tests the pagerduty connection"

    it "sends an event to pagerduty"

  end

end
