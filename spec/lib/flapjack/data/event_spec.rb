require 'spec_helper'
require 'flapjack/data/event'

describe Flapjack::Data::Event, :redis => true do

  it "creates an acknowledgement" # do
    # ec = Flapjack::Data::EntityCheck.for_entity_name(name, check, :redis => @redis)
    # t = Time.now.to_i
    # ec.create_acknowledgement('summary'            => 'looking now',
    #                           'time'               => t,
    #                           'acknowledgement_id' => '75',
    #                           'duration'           => 40 * 60)
    # event_json = @redis.rpop('events')
    # event_json.should_not be_nil
    # event = nil
    # expect {
    #   event = JSON.parse(event_json)
    # }.not_to raise_error
    # event.should_not be_nil
    # event.should be_a(Hash)
    # event.should == {
    #   'entity'             => name,
    #   'check'              => check,
    #   'type'               => 'action',
    #   'state'              => 'acknowledgement',
    #   'summary'            => 'looking now',
    #   'time'               => t,
    #   'acknowledgement_id' => '75',
    #   'duration'           => 2400
    # }
  # end

end