require 'spec_helper'
require 'flapjack/api'

describe 'Flapjack::API', :sinatra => true do

  def app
    Flapjack::API
  end

  before(:each) do
    # needs to be defined, but should not be accessed
    Flapjack::API.class_variable_set('@@redis', mock('redis'))
  end

  let(:entity)          { mock('entity') }
  let(:entity_name)     { 'example.com'}
  let(:entity_name_esc) { URI.escape(entity_name) }

  it "returns a list of checks for an entity" do
    check_list = ['ping']
    entity.should_receive(:check_list).and_return(check_list)
    Flapjack::Data::Entity.should_receive(:find_by_name).with(entity_name, an_instance_of(Hash)).and_return(entity)

    get "/checks/#{entity_name_esc}"
    last_response.should be_ok
    last_response.body.should == check_list.to_json
  end

end