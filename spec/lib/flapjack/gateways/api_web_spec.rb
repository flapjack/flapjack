require 'spec_helper'
require 'flapjack/gateways/api_web'

describe Flapjack::Gateways::ApiWeb, :sinatra => true, :pact_fixture => true, :logger => true do

  def app
    Flapjack::Gateways::ApiWeb
  end

  # let(:check_name)      { 'example.com:ping' }

  # let(:check)  { double(Flapjack::Data::Check, :id => check_data[:id]) }
  # let(:states) { double('states') }

  let(:redis)  { double(Redis) }

  let(:config) { {
    'api_url' => 'http://localhost:5081/'
  } }

  before(:all) do
    Flapjack::Gateways::ApiWeb.set :raise_errors, true
  end

  before(:each) do
    allow(Flapjack).to receive(:redis).and_return(redis)
  end

  # TODO add more data, test that pages contain representations of it

  context "web page design" do

    it "displays a custom logo if configured" do
      image_path = '/tmp/branding.png'

      allow(File).to receive(:file?).and_call_original
      allow(File).to receive(:file?).with(image_path) { true }

      Flapjack::Gateways::ApiWeb.instance_variable_set('@config',
        config.merge({"logo_image_path" => image_path}))
      Flapjack::Gateways::ApiWeb.start

      expect(Flapjack::Diner).to receive(:statistics).and_return([global_statistics_data])
      expect(Flapjack::Diner).to receive(:metrics).and_return(metrics_data)

      logo_image_tag = '<img alt="Flapjack" class="logo" src="http://example.org/img/branding.png">'

      get '/self_stats'

      expect( last_response.body ).to include(logo_image_tag)
    end

    it "displays the standard logo if no custom logo configured" do
      Flapjack::Gateways::ApiWeb.instance_variable_set('@config', config)
      Flapjack::Gateways::ApiWeb.start

      expect(Flapjack::Diner).to receive(:statistics).and_return([global_statistics_data])
      expect(Flapjack::Diner).to receive(:metrics).and_return(metrics_data)

      logo_image_tag = '<img alt="Flapjack" class="logo" src="http://example.org/img/flapjack-2013-notext-transparent-300-300.png">'

      get '/self_stats'

      expect( last_response.body ).to include(logo_image_tag)
    end
  end

  context 'web page behaviour' do

    before(:each) do
      Flapjack::Gateways::ApiWeb.instance_variable_set('@config', config)
      Flapjack::Gateways::ApiWeb.start
    end

    it "shows a page listing all checks" do
      expect(Flapjack::Diner).to receive(:checks).with(:filter => {},
        :page => 1, :include => ['current_state', 'latest_notifications',
                                 'current_scheduled_maintenances',
                                 'current_unscheduled_maintenance']).
      and_return([])

      get '/checks'
      expect(last_response).to be_ok
    end

    it "shows a page listing failing checks" do
      expect(Flapjack::Diner).to receive(:checks).with(:filter => {:failing => true},
        :page => 1, :include => ['current_state', 'latest_notifications',
                                 'current_scheduled_maintenances',
                                 'current_unscheduled_maintenance']).
      and_return([])

      get '/checks?failing=t'
      expect(last_response).to be_ok
    end

    it "shows a page listing flapjack statistics" do
      expect(Flapjack::Diner).to receive(:statistics).and_return([global_statistics_data])
      expect(Flapjack::Diner).to receive(:metrics).and_return(metrics_data)

      get '/self_stats'
      expect(last_response).to be_ok
    end

    it "shows the state of a check" do
      resp_data = check_json(check_data).merge(:relationships => check_rel(check_data))
      resp_data[:relationships][:contacts][:data] = [
        {:type => 'contact', :id => contact_data[:id]}
      ]
      resp_data[:relationships][:current_state][:data] =
        {:type => 'state', :id => state_data[:id]}
      resp_data[:relationships][:latest_notifications][:data] = []
      resp_data[:relationships][:current_scheduled_maintenances][:data] = []
      resp_data[:relationships][:current_unscheduled_maintenance][:data] = nil

      resp_contact = contact_json(contact_data).merge(:relationships => contact_rel(contact_data))
      resp_contact[:relationships][:media][:data] = [
        {:type => 'medium', :id => email_data[:id]}
      ]

      resp_state = state_json(state_data).merge(:relationships => state_rel(state_data))

      resp_included = [
        resp_contact,
        medium_json(email_data).merge(:relationships => medium_rel(email_data)),
        resp_state
      ]

      expect(Flapjack::Diner).to receive(:checks).
        with(check_data[:id], :include => ['contacts.media', 'current_state',
                                           'latest_notifications',
                                           'current_scheduled_maintenances',
                                           'current_unscheduled_maintenance']).
        and_return(resp_data)

      expect(Flapjack::Diner).to receive(:check_link_states).
        with(check_data[:id], :include => 'states').
        and_return([{:type => 'state', :id => state_data[:id]}])

      expect(Flapjack::Diner).to receive(:check_link_scheduled_maintenances).
        with(check_data[:id], :include => 'scheduled_maintenances').
        and_return([])

      expect(Flapjack::Diner).to receive(:context).exactly(3).times.
        and_return({:included => resp_included}, {:included => [resp_state]},
          {:included => []})

      get "/checks/#{check_data[:id]}"
      expect(last_response).to be_ok
    end

    it "returns 404 if an unknown check is requested" do
      expect(Flapjack::Diner).to receive(:checks).
        with(check_data[:id], :include => ['contacts.media', 'current_state',
                                           'latest_notifications',
                                           'current_scheduled_maintenances',
                                           'current_unscheduled_maintenance']).
        and_return(nil)

      get "/checks/#{check_data[:id]}"
      expect(last_response).to be_not_found
    end

    it "creates an acknowledgement for a check" do
      expect(Flapjack::Diner).to receive(:create_acknowledgements).
        with(:summary => 'oh no', :duration => 3600, :check => check_data[:id]).
        and_return(true)

      post "/acknowledgements", {:check_id => check_data[:id],
        :duration => '1 hour', :summary => 'oh no'}
      expect(last_response.status).to eq(302)
    end

    it "creates a scheduled maintenance period for a check" do
      expect(Flapjack::Diner).to receive(:create_scheduled_maintenances).
        with(:summary => 'wow', :start_time => an_instance_of(Time),
             :end_time => an_instance_of(Time), :check => check_data[:id]).
        and_return(true)

      post "/scheduled_maintenances", {:check_id => check_data[:id],
        :start_time => '1 day ago', :duration => '30 minutes', :summary => 'wow'}

      expect(last_response.status).to eq(302)
    end

    it "deletes a scheduled maintenance period for a check" do
      expect(Flapjack::Diner).to receive(:delete_scheduled_maintenances).
        with(scheduled_maintenance_data[:id]).and_return(true)

      delete "/scheduled_maintenances/#{scheduled_maintenance_data[:id]}"
      expect(last_response.status).to eq(302)
    end

    it "shows a list of all known contacts" do
      resp_data = [contact_json(contact_data).merge(:relationships => contact_rel(contact_data))]

      expect(Flapjack::Diner).to receive(:contacts).with(:filter => {},
        :page => 1, :sort => '+name').and_return(resp_data)

      get "/contacts"
      expect(last_response).to be_ok
    end

    it "shows details of an individual contact found by id" do
      resp_data = contact_json(contact_data).merge(:relationships => contact_rel(contact_data))
      resp_data[:relationships][:checks][:data] = [
        {:type => 'check', :id => check_data[:id]}
      ]
      resp_data[:relationships][:media][:data] = [
        {:type => 'medium', :id => email_data[:id]}
      ]
      resp_data[:relationships][:acceptors][:data] = [
      ]
      resp_data[:relationships][:rejectors][:data] = [
      ]

      resp_included = [
        check_json(check_data).merge(:relationships => check_rel(check_data)),
        medium_json(email_data).merge(:relationships => medium_rel(email_data))
      ]

      expect(Flapjack::Diner).to receive(:contacts).
        with(contact_data[:id], :include => ['acceptors', 'checks', 'media', 'rejectors']).
        and_return(resp_data)

      expect(Flapjack::Diner).to receive(:context).
        and_return({:included => resp_included})

      get "/contacts/#{contact_data[:id]}"
      expect(last_response).to be_ok
    end
  end
end
