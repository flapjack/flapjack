require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::Events', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:acknowledgement) { double(Flapjack::Data::Acknowledgement, :id => acknowledgement_data[:id]) }
  let(:test_notification) { double(Flapjack::Data::TestNotification, :id => test_notification_data[:id]) }
  let(:test_notification_2) { double(Flapjack::Data::TestNotification, :id => test_notification_2_data[:id]) }

  let(:check)  { double(Flapjack::Data::Check, :id => check_data[:id]) }
  let(:tag)    { double(Flapjack::Data::Tag, :id => tag_data[:id]) }

  let(:queue) { 'events' }

  context 'acknowledgements' do

    it "creates an acknowledgement for a check" do
      expect(Flapjack::Data::Check).to receive(:find_by_id!).
        with(check.id).and_return(check)

      expect(acknowledgement).to receive(:invalid?).and_return(false)
      expect(acknowledgement).to receive(:queue=).with(queue)
      expect(acknowledgement).to receive(:save!).and_return(true)
      expect(acknowledgement).to receive(:"check=").with(check)

      expect(Flapjack::Data::Acknowledgement).to receive(:new).
        with(acknowledgement_data).
        and_return(acknowledgement)

      expect(acknowledgement).to receive(:as_json).with(:only => an_instance_of(Array)).
        and_return(acknowledgement_data.reject {|k,v| :id.eql?(k)})

      req_data  = acknowledgement_json(acknowledgement_data).merge(
        :relationships => {
          :check => {
            :data => {:type => 'check', :id => check.id}
          }
        }
      )
      resp_data = acknowledgement_json(acknowledgement_data)

      post "/acknowledgements", Flapjack.dump_json(:data => req_data),
        jsonapi_env
      expect(last_response.status).to eq(201)
      expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data =>
        resp_data
      ))
    end

    it 'creates acknowledgements for checks linked to a tag' do
      expect(Flapjack::Data::Tag).to receive(:find_by_id!).
        with(tag.id).and_return(tag)

      expect(acknowledgement).to receive(:invalid?).and_return(false)
      expect(acknowledgement).to receive(:queue=).with(queue)
      expect(acknowledgement).to receive(:save!).and_return(true)
      expect(acknowledgement).to receive(:"tag=").with(tag)

      expect(Flapjack::Data::Acknowledgement).to receive(:new).
        with(acknowledgement_data).
        and_return(acknowledgement)

      expect(acknowledgement).to receive(:as_json).with(:only => an_instance_of(Array)).
        and_return(acknowledgement_data.reject {|k,v| :id.eql?(k)})

      req_data  = acknowledgement_json(acknowledgement_data).merge(
        :relationships => {
          :tag => {
            :data => {:type => 'tag', :id => tag.id}
          }
        }
      )
      resp_data = acknowledgement_json(acknowledgement_data)

      post "/acknowledgements", Flapjack.dump_json(:data => req_data),
        jsonapi_env
      expect(last_response.status).to eq(201)
      expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data =>
        resp_data
      ))
    end

  end

  context 'test_notifications' do

    it "creates a test notification for a check" do
      expect(Flapjack::Data::Check).to receive(:find_by_id!).
        with(check.id).and_return(check)

      expect(test_notification).to receive(:invalid?).and_return(false)
      expect(test_notification).to receive(:queue=).with(queue)
      expect(test_notification).to receive(:save!).and_return(true)
      expect(test_notification).to receive(:"check=").with(check)

      expect(Flapjack::Data::TestNotification).to receive(:new).
        with(test_notification_data).
        and_return(test_notification)

      expect(test_notification).to receive(:as_json).with(:only => an_instance_of(Array)).
        and_return(test_notification_data.reject {|k,v| :id.eql?(k)})

      req_data  = test_notification_json(test_notification_data).merge(
        :relationships => {
          :check => {
            :data => {:type => 'check', :id => check.id}
          }
        }
      )
      resp_data = test_notification_json(test_notification_data)

      post "/test_notifications", Flapjack.dump_json(:data => req_data),
        jsonapi_env
      expect(last_response.status).to eq(201)
      expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data =>
        resp_data
      ))
    end

    it 'creates test notifications for checks linked to a tag' do
      expect(Flapjack::Data::Tag).to receive(:find_by_id!).
        with(tag.id).and_return(tag)

      expect(test_notification).to receive(:invalid?).and_return(false)
      expect(test_notification).to receive(:queue=).with(queue)
      expect(test_notification).to receive(:save!).and_return(true)
      expect(test_notification).to receive(:"tag=").with(tag)

      expect(Flapjack::Data::TestNotification).to receive(:new).
        with(test_notification_data).
        and_return(test_notification)

      expect(test_notification).to receive(:as_json).with(:only => an_instance_of(Array)).
        and_return(test_notification_data.reject {|k,v| :id.eql?(k)})

      req_data  = test_notification_json(test_notification_data).merge(
        :relationships => {
          :tag => {
            :data => {:type => 'tag', :id => tag.id}
          }
        }
      )
      resp_data = test_notification_json(test_notification_data)

      post "/test_notifications", Flapjack.dump_json(:data => req_data),
        jsonapi_env
      expect(last_response.status).to eq(201)
      expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data =>
        resp_data
      ))
    end

    it 'creates multiple test notifications for a check' do
      expect(Flapjack::Data::Check).to receive(:find_by_id!).
        with(check.id).twice.and_return(check)

      expect(test_notification).to receive(:invalid?).and_return(false)
      expect(test_notification).to receive(:queue=).with(queue)
      expect(test_notification).to receive(:save!).and_return(true)
      expect(test_notification).to receive(:"check=").with(check)

      expect(test_notification_2).to receive(:invalid?).and_return(false)
      expect(test_notification_2).to receive(:queue=).with(queue)
      expect(test_notification_2).to receive(:save!).and_return(true)
      expect(test_notification_2).to receive(:"check=").with(check)

      expect(Flapjack::Data::TestNotification).to receive(:new).
        with(test_notification_data).
        and_return(test_notification)

      expect(Flapjack::Data::TestNotification).to receive(:new).
        with(test_notification_2_data).
        and_return(test_notification_2)

      expect(test_notification).to receive(:as_json).with(:only => an_instance_of(Array)).
        and_return(test_notification_data.reject {|k,v| :id.eql?(k)})

      expect(test_notification_2).to receive(:as_json).with(:only => an_instance_of(Array)).
        and_return(test_notification_2_data.reject {|k,v| :id.eql?(k)})

      req_data  = [
        test_notification_json(test_notification_data).merge(
          :relationships => {
            :check => {
              :data => {:type => 'check', :id => check.id}
            }
          }
        ),
        test_notification_json(test_notification_2_data).merge(
          :relationships => {
            :check => {
              :data => {:type => 'check', :id => check.id}
            }
          }
        )
      ]
      resp_data = [
        test_notification_json(test_notification_data),
        test_notification_json(test_notification_2_data),
      ]

      post "/test_notifications", Flapjack.dump_json(:data => req_data),
        jsonapi_bulk_env
      expect(last_response.status).to eq(201)
      expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data =>
        resp_data
      ))
    end

    it 'creates multiple test notifications for checks linked to a tag' do
      expect(Flapjack::Data::Tag).to receive(:find_by_id!).
        with(tag.id).twice.and_return(tag)

      expect(test_notification).to receive(:invalid?).and_return(false)
      expect(test_notification).to receive(:queue=).with(queue)
      expect(test_notification).to receive(:save!).and_return(true)
      expect(test_notification).to receive(:"tag=").with(tag)

      expect(test_notification_2).to receive(:invalid?).and_return(false)
      expect(test_notification_2).to receive(:queue=).with(queue)
      expect(test_notification_2).to receive(:save!).and_return(true)
      expect(test_notification_2).to receive(:"tag=").with(tag)

      expect(Flapjack::Data::TestNotification).to receive(:new).
        with(test_notification_data).
        and_return(test_notification)

      expect(Flapjack::Data::TestNotification).to receive(:new).
        with(test_notification_2_data).
        and_return(test_notification_2)

      expect(test_notification).to receive(:as_json).with(:only => an_instance_of(Array)).
        and_return(test_notification_data.reject {|k,v| :id.eql?(k)})

      expect(test_notification_2).to receive(:as_json).with(:only => an_instance_of(Array)).
        and_return(test_notification_2_data.reject {|k,v| :id.eql?(k)})

      req_data  = [
        test_notification_json(test_notification_data).merge(
          :relationships => {
            :tag => {
              :data => {:type => 'tag', :id => tag.id}
            }
          }
        ),
        test_notification_json(test_notification_2_data).merge(
          :relationships => {
            :tag => {
              :data => {:type => 'tag', :id => tag.id}
            }
          }
        )
      ]
      resp_data = [
        test_notification_json(test_notification_data),
        test_notification_json(test_notification_2_data),
      ]

      post "/test_notifications", Flapjack.dump_json(:data => req_data),
        jsonapi_bulk_env
      expect(last_response.status).to eq(201)
      expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data =>
        resp_data
      ))
    end

  end

end
