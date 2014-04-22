require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::MediumMethods', :sinatra => true, :logger => true do

  def app
    Flapjack::Gateways::JSONAPI
  end

  let(:medium_data) {
    {:type => 'email',
     :address => 'abc@example.com',
     :interval => 120,
     :rollup_threshold => 3
    }
  }

  let(:contact) { double(Flapjack::Data::Contact, :id => '21') }

  let(:redis) { double(::Redis) }

  let(:semaphore) {
    double(Flapjack::Data::Semaphore, :resource => 'folly',
           :key => 'semaphores:folly', :expiry => 30, :token => 'spatulas-R-us')
  }

  let(:jsonapi_env) {
    {'CONTENT_TYPE' => Flapjack::Gateways::JSONAPI::JSONAPI_MEDIA_TYPE,
     'HTTP_ACCEPT'  => 'application/json; q=0.8, application/vnd.api+json'}
  }

  before(:all) do
    Flapjack::Gateways::JSONAPI.class_eval {
      set :raise_errors, true
    }
  end

  before(:each) do
    expect(Flapjack::RedisPool).to receive(:new).and_return(redis)
    Flapjack::Gateways::JSONAPI.instance_variable_set('@config', {})
    Flapjack::Gateways::JSONAPI.instance_variable_set('@logger', @logger)
    Flapjack::Gateways::JSONAPI.start
  end

  after(:each) do
    if last_response.status >= 200 && last_response.status < 300
      expect(last_response.headers.keys).to include('Access-Control-Allow-Methods')
      expect(last_response.headers['Access-Control-Allow-Origin']).to eq("*")
      unless last_response.status == 204
        expect(Oj.load(last_response.body)).to be_a(Enumerable)
        expect(last_response.headers['Content-Type']).to eq(Flapjack::Gateways::JSONAPI::JSONAPI_MEDIA_TYPE)
      end
    end
  end

  it "returns a single medium" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, :redis => redis, :logger => @logger).and_return(contact)

    expect(contact).to receive(:media).and_return(medium_data[:type] => medium_data[:address])
    expect(contact).to receive(:media_intervals).and_return(medium_data[:type] => medium_data[:interval])
    expect(contact).to receive(:media_rollup_thresholds).and_return(medium_data[:type] => medium_data[:rollup_threshold])

    aget "/media/#{contact.id}_#{medium_data[:type]}", {}, jsonapi_env
    expect(last_response).to be_ok
    expect(last_response.body).to eq({:media => [{:id => "#{contact.id}_#{medium_data[:type]}"}.merge(medium_data).
        merge(:links => {:contacts => [contact.id]})]}.to_json)
  end

  it "returns multiple media" do
    contact_2 = double(Flapjack::Data::Contact, :id => '53')

    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, :redis => redis, :logger => @logger).and_return(contact)
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact_2.id, :redis => redis, :logger => @logger).and_return(contact_2)

    expect(contact).to receive(:media).and_return(medium_data[:type] => medium_data[:address])
    expect(contact).to receive(:media_intervals).and_return(medium_data[:type] => medium_data[:interval])
    expect(contact).to receive(:media_rollup_thresholds).and_return(medium_data[:type] => medium_data[:rollup_threshold])

    medium_2_data = {:type => 'sms', :address => '0123456789',
     :interval => 120, :rollup_threshold => 3}

    expect(contact_2).to receive(:media).and_return(medium_2_data[:type] => medium_2_data[:address])
    expect(contact_2).to receive(:media_intervals).and_return(medium_2_data[:type] => medium_2_data[:interval])
    expect(contact_2).to receive(:media_rollup_thresholds).and_return(medium_2_data[:type] => medium_2_data[:rollup_threshold])

    aget "/media/#{contact.id}_#{medium_data[:type]},#{contact_2.id}_#{medium_2_data[:type]}", {}, jsonapi_env
    expect(last_response).to be_ok
    expect(last_response.body).to eq({:media => [{:id => "#{contact.id}_#{medium_data[:type]}"}.merge(medium_data).
        merge(:links => {:contacts => [contact.id]}),
        {:id => "#{contact_2.id}_#{medium_2_data[:type]}"}.merge(medium_2_data).
        merge(:links => {:contacts => [contact_2.id]})]}.to_json)
  end

  it "returns all media" do
    expect(Flapjack::Data::Contact).to receive(:all).
      with(:redis => redis).and_return([contact])

    expect(contact).to receive(:media_list).and_return([medium_data[:type]])
    expect(contact).to receive(:media).and_return(medium_data[:type] => medium_data[:address])
    expect(contact).to receive(:media_intervals).and_return(medium_data[:type] => medium_data[:interval])
    expect(contact).to receive(:media_rollup_thresholds).and_return(medium_data[:type] => medium_data[:rollup_threshold])

    aget '/media', {}, jsonapi_env
    expect(last_response).to be_ok
    expect(last_response.body).to eq({:media => [{:id => "#{contact.id}_#{medium_data[:type]}"}.merge(medium_data).
        merge(:links => {:contacts => [contact.id]})]}.to_json)
  end

  it "does not return a medium if the contact is not present" do
    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, :redis => redis, :logger => @logger).and_return(nil)

    aget "/media/#{contact.id}_email", {}, jsonapi_env
    expect(last_response.status).to eq(404)
  end

  it "does not return a medium if the medium is not present"

  it "creates a medium for a contact" do
    expect(Flapjack::Data::Semaphore).to receive(:new).
      with("contact_mass_update", :redis => redis, :expiry => 30).and_return(semaphore)

    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(contact)

    expect(contact).to receive(:set_address_for_media).
      with(medium_data[:type], medium_data[:address])
    expect(contact).to receive(:set_interval_for_media).
      with(medium_data[:type], medium_data[:interval])
    expect(contact).to receive(:set_rollup_threshold_for_media).
      with(medium_data[:type], medium_data[:rollup_threshold])

    expect(semaphore).to receive(:release).and_return(true)

    apost "/contacts/#{contact.id}/media", {:media => [medium_data]}.to_json, jsonapi_env
    expect(last_response.status).to eq(201)
    expect(last_response.body).to eq('{"media":[' +
      medium_data.merge(:id => "#{contact.id}_email",
                        :links => {:contacts => [contact.id]}).to_json + ']}')
  end

  it "does not create a medium for a contact that's not present" do
    expect(Flapjack::Data::Semaphore).to receive(:new).
      with("contact_mass_update", :redis => redis, :expiry => 30).and_return(semaphore)

    expect(Flapjack::Data::Contact).to receive(:find_by_id).
      with(contact.id, :redis => redis).and_return(nil)

    medium_data = {:type => 'email',
      :address => 'abc@example.com', :interval => 120, :rollup_threshold => 3}

    expect(semaphore).to receive(:release).and_return(true)

    apost "/contacts/#{contact.id}/media", {:media => [medium_data]}.to_json, jsonapi_env
    expect(last_response.status).to eq(422)
  end

  it "updates a medium"

  it "deletes a medium"

  it "does not delete a medium that's not found"

end
