require 'spec_helper'
require 'flapjack/web'

# TODO move the rest of the redis operations down to data models, then this
# test won't need read/write redis data

describe Flapjack::Web, :sinatra => true, :redis => true do

  def app
    Flapjack::Web
  end

  let(:entity_name)     { 'example.com'}
  let(:entity_name_esc) { URI.escape(entity_name) }

  let(:entity)          { mock(Flapjack::Data::Entity) }
  let(:entity_check)    { mock(Flapjack::Data::EntityCheck) }

  before(:each) do
    Flapjack::Web.class_variable_set('@@redis', @redis)
  end

  # TODO add data, test that pages contain representations of it

  it "shows a page listing all checks" do
    get '/'
    last_response.should be_ok
  end

  it "shows a page listing failing checks" do
    get '/failing'
    last_response.should be_ok
  end

  it "shows a page listing flapjack statistics" do
    get '/self_stats'
    last_response.should be_ok
  end

  it "shows the state of a check for an entity" do
    t = Time.now.to_i

    entity_check.should_receive(:state).and_return('ok')
    entity_check.should_receive(:last_update).and_return(t - (3 * 60 * 60))
    entity_check.should_receive(:last_change).and_return(t - (3 * 60 * 60))
    entity_check.should_receive(:summary).and_return('all good')
    entity_check.should_receive(:last_problem_notification).and_return(t - ((3 * 60 * 60) + (5 * 60)))
    entity_check.should_receive(:last_recovery_notification).and_return(t - (3 * 60 * 60))
    entity_check.should_receive(:last_acknowledgement_notification).and_return(nil)
    entity_check.should_receive(:in_scheduled_maintenance?).and_return(false)
    entity_check.should_receive(:in_unscheduled_maintenance?).and_return(false)
    entity_check.should_receive(:scheduled_maintenances).and_return([])

    Flapjack::Data::Entity.should_receive(:find_by_name).
      with(entity_name, :redis => @redis).and_return(entity)

    Flapjack::Data::EntityCheck.should_receive(:for_entity).
      with(entity, 'ping', :redis => @redis).and_return(entity_check)

    get "/check?entity=#{entity_name_esc}&check=ping"
    last_response.should be_ok
    # TODO test instance variables set to appropriate values
  end

  it "returns 404 if an unknown entity is requested" do
    get "/check?entity=#{entity_name_esc}&check=ping"
    last_response.should be_not_found
  end

  it "returns 404 if no entity check is passed" do
    Flapjack::Data::Entity.add({'id'   => '5000',
                                'name' => entity_name},
                               :redis => @redis)
    get "/check?entity=#{entity_name_esc}"
    last_response.should be_not_found
  end

  # TODO this should not be a GET
  it "creates an acknowledgement for an entity check" do

  end

  it "creates a scheduled maintenance period for an entity check" do

  end

  it "deletes a scheduled maintenance period for an entity check"

end