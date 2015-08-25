require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::UnscheduledMaintenances', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:unscheduled_maintenance) { double(Flapjack::Data::UnscheduledMaintenance,
    :id => unscheduled_maintenance_data[:id]) }
  let(:unscheduled_maintenance_2) { double(Flapjack::Data::UnscheduledMaintenance,
    :id => unscheduled_maintenance_2_data[:id]) }

  let(:check) { double(Flapjack::Data::Check, :id => check_data[:id]) }

  it "cannot create an unscheduled maintenance period" do
    req_data  = maintenance_json('unscheduled', unscheduled_maintenance_data)

    post "/unscheduled_maintenances", Flapjack.dump_json(:data => req_data), jsonapi_env
    expect(last_response.status).to eq(404)
  end

  it 'returns a single unscheduled maintenance period' do
    expect(Flapjack::Data::UnscheduledMaintenance).to receive(:lock).
      with(no_args).
      and_yield

    expect(Flapjack::Data::UnscheduledMaintenance).to receive(:intersect).
      with(:id => Set.new([unscheduled_maintenance.id])).and_return([unscheduled_maintenance])

    expect(unscheduled_maintenance).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(unscheduled_maintenance_data.reject {|k,v| :id.eql?(k)})

    resp_data = maintenance_json('unscheduled', unscheduled_maintenance_data).
      merge(:relationships => maintenance_rel('unscheduled', unscheduled_maintenance_data))

    get "/unscheduled_maintenances/#{unscheduled_maintenance.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(:data => resp_data,
      :links => {:self  => "http://example.org/unscheduled_maintenances/#{unscheduled_maintenance.id}"}))
  end

  it 'returns multiple unscheduled_maintenance periods' do
    expect(Flapjack::Data::UnscheduledMaintenance).to receive(:lock).
      with(no_args).
      and_yield

    meta = {
      :pagination => {
        :page        => 1,
        :per_page    => 20,
        :total_pages => 1,
        :total_count => 2
      }
    }

    links = {
      :self  => "http://example.org/unscheduled_maintenances?filter%5B%5D=id%3A#{unscheduled_maintenance.id}%7C#{unscheduled_maintenance_2.id}",
      :first => "http://example.org/unscheduled_maintenances?filter%5B%5D=id%3A#{unscheduled_maintenance.id}%7C#{unscheduled_maintenance_2.id}&page=1",
      :last  => "http://example.org/unscheduled_maintenances?filter%5B%5D=id%3A#{unscheduled_maintenance.id}%7C#{unscheduled_maintenance_2.id}&page=1"
    }

    page = double('page')
    expect(page).to receive(:empty?).and_return(false)
    expect(page).to receive(:ids).and_return([unscheduled_maintenance.id, unscheduled_maintenance_2.id])
    expect(page).to receive(:collect) {|&arg| [arg.call(unscheduled_maintenance), arg.call(unscheduled_maintenance_2)] }

    sorted = double('sorted')
    expect(sorted).to receive(:page).with(1, :per_page => 20).and_return(page)
    expect(sorted).to receive(:count).and_return(2)

    filtered = double('filtered')
    expect(filtered).to receive(:sort).with(:id).and_return(sorted)
    expect(Flapjack::Data::UnscheduledMaintenance).to receive(:intersect).with(:id => [unscheduled_maintenance.id, unscheduled_maintenance_2.id]).
      and_return(filtered)

    expect(unscheduled_maintenance).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(unscheduled_maintenance_data.reject {|k,v| :id.eql?(k)})

    expect(unscheduled_maintenance_2).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(unscheduled_maintenance_2_data.reject {|k,v| :id.eql?(k)})

    resp_data = [
      maintenance_json('unscheduled', unscheduled_maintenance_data).
        merge(:relationships => maintenance_rel('unscheduled', unscheduled_maintenance_data)),
      maintenance_json('unscheduled', unscheduled_maintenance_2_data).
        merge(:relationships => maintenance_rel('unscheduled', unscheduled_maintenance_2_data))
    ]

    get "/unscheduled_maintenances?filter=id%3A#{unscheduled_maintenance.id}%7C#{unscheduled_maintenance_2.id}"
    expect(last_response).to be_ok
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data => resp_data,
      :links => links, :meta => meta))
  end

  it 'returns paginated unscheduled maintenance periods' do
    expect(Flapjack::Data::UnscheduledMaintenance).to receive(:lock).
      with(no_args).
      and_yield

    meta = {
      :pagination => {
        :page        => 1,
        :per_page    => 20,
        :total_pages => 1,
        :total_count => 1
      }
    }

    links = {
      :self  => 'http://example.org/unscheduled_maintenances',
      :first => 'http://example.org/unscheduled_maintenances?page=1',
      :last  => 'http://example.org/unscheduled_maintenances?page=1'
    }

    page = double('page')
    expect(page).to receive(:empty?).and_return(false)
    expect(page).to receive(:ids).and_return([unscheduled_maintenance.id])
    expect(page).to receive(:collect) {|&arg| [arg.call(unscheduled_maintenance)] }
    sorted = double('sorted')
    expect(sorted).to receive(:page).with(1, :per_page => 20).
      and_return(page)
    expect(sorted).to receive(:count).and_return(1)
    expect(Flapjack::Data::UnscheduledMaintenance).to receive(:sort).
      with(:id).and_return(sorted)

    expect(unscheduled_maintenance).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(unscheduled_maintenance_data.reject {|k,v| :id.eql?(k)})

    resp_data = [maintenance_json('unscheduled', unscheduled_maintenance_data).
      merge(:relationships => maintenance_rel('unscheduled', unscheduled_maintenance_data))]

    get '/unscheduled_maintenances'
    expect(last_response).to be_ok
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data => resp_data, :links => links, :meta => meta))
  end

  it "queries unscheduled maintenance periods by a closed date range" do
    expect(Flapjack::Data::UnscheduledMaintenance).to receive(:lock).
      with(no_args).
      and_yield

    meta = {
      :pagination => {
        :page        => 1,
        :per_page    => 20,
        :total_pages => 1,
        :total_count => 1
      }
    }

    st_t = fixture_time - 1_000
    ft_t = fixture_time + 4_000
    st = CGI::escape(st_t.iso8601)
    ft = CGI::escape(ft_t.iso8601)

    links = {
       :first => "http://example.org/unscheduled_maintenances?filter%5B%5D=start_time%3A#{st}..#{ft}&page=1",
       :last  => "http://example.org/unscheduled_maintenances?filter%5B%5D=start_time%3A#{st}..#{ft}&page=1",
       :self  => "http://example.org/unscheduled_maintenances?filter%5B%5D=start_time%3A#{st}..#{ft}"
    }

    page = double('page')
    expect(page).to receive(:empty?).and_return(false)
    expect(page).to receive(:ids).and_return([unscheduled_maintenance.id])
    expect(page).to receive(:collect) {|&arg| [arg.call(unscheduled_maintenance)] }
    sorted = double('sorted')
    expect(sorted).to receive(:page).with(1, :per_page => 20).
      and_return(page)
    expect(sorted).to receive(:count).and_return(1)

    time_filter = double(Zermelo::Filters::IndexRange)
    expect(Zermelo::Filters::IndexRange).to receive(:new).
      with(st_t.to_datetime, ft_t.to_datetime, :by_score => true).and_return(time_filter)

    filtered = double('filtered')
    expect(Flapjack::Data::UnscheduledMaintenance).to receive(:intersect).
      with(:start_time => time_filter).and_return(filtered)
    expect(filtered).to receive(:sort).with(:id).and_return(sorted)

    expect(unscheduled_maintenance).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(unscheduled_maintenance_data.reject {|k,v| :id.eql?(k)})

    resp_data = [maintenance_json('unscheduled', unscheduled_maintenance_data).
      merge(:relationships => maintenance_rel('unscheduled', unscheduled_maintenance_data))]

    get "/unscheduled_maintenances?filter=start_time%3A#{st}..#{ft}"
    expect(last_response).to be_ok
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data => resp_data, :links => links, :meta => meta))
  end

  it "queries unscheduled maintenance periods by an open date range" do
    expect(Flapjack::Data::UnscheduledMaintenance).to receive(:lock).
      with(no_args).
      and_yield

    meta = {
      :pagination => {
        :page        => 1,
        :per_page    => 20,
        :total_pages => 1,
        :total_count => 1
      }
    }

    st_t = fixture_time - 1_000
    st = CGI::escape(st_t.iso8601)

    links = {
       :first => "http://example.org/unscheduled_maintenances?filter%5B%5D=start_time%3A#{st}..&page=1",
       :last  => "http://example.org/unscheduled_maintenances?filter%5B%5D=start_time%3A#{st}..&page=1",
       :self  => "http://example.org/unscheduled_maintenances?filter%5B%5D=start_time%3A#{st}.."
    }

    page = double('page')
    expect(page).to receive(:empty?).and_return(false)
    expect(page).to receive(:ids).and_return([unscheduled_maintenance.id])
    expect(page).to receive(:collect) {|&arg| [arg.call(unscheduled_maintenance)] }
    sorted = double('sorted')
    expect(sorted).to receive(:page).with(1, :per_page => 20).
      and_return(page)
    expect(sorted).to receive(:count).and_return(1)

    time_filter = double(Zermelo::Filters::IndexRange)
    expect(Zermelo::Filters::IndexRange).to receive(:new).
      with(st_t.to_datetime, nil, :by_score => true).and_return(time_filter)

    filtered = double('filtered')
    expect(Flapjack::Data::UnscheduledMaintenance).to receive(:intersect).
      with(:start_time => time_filter).and_return(filtered)
    expect(filtered).to receive(:sort).with(:id).and_return(sorted)

    expect(unscheduled_maintenance).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(unscheduled_maintenance_data.reject {|k,v| :id.eql?(k)})

    resp_data = [maintenance_json('unscheduled', unscheduled_maintenance_data).
      merge(:relationships => maintenance_rel('unscheduled', unscheduled_maintenance_data))]

    get "/unscheduled_maintenances?filter=start_time%3A#{st}.."
    expect(last_response).to be_ok
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data => resp_data, :links => links, :meta => meta))
  end

  it "queries unscheduled maintenance periods by exact date" do
    expect(Flapjack::Data::UnscheduledMaintenance).to receive(:lock).
      with(no_args).
      and_yield

    meta = {
      :pagination => {
        :page        => 1,
        :per_page    => 20,
        :total_pages => 1,
        :total_count => 1
      }
    }

    st_t = fixture_time
    st = CGI::escape(st_t.iso8601)

    links = {
       :first => "http://example.org/unscheduled_maintenances?filter%5B%5D=start_time%3A#{st}&page=1",
       :last  => "http://example.org/unscheduled_maintenances?filter%5B%5D=start_time%3A#{st}&page=1",
       :self  => "http://example.org/unscheduled_maintenances?filter%5B%5D=start_time%3A#{st}"
    }

    page = double('page')
    expect(page).to receive(:empty?).and_return(false)
    expect(page).to receive(:ids).and_return([unscheduled_maintenance.id])
    expect(page).to receive(:collect) {|&arg| [arg.call(unscheduled_maintenance)] }
    sorted = double('sorted')
    expect(sorted).to receive(:page).with(1, :per_page => 20).
      and_return(page)
    expect(sorted).to receive(:count).and_return(1)

    filtered = double('filtered')
    expect(Flapjack::Data::UnscheduledMaintenance).to receive(:intersect).
      with(:start_time => st.to_datetime).and_return(filtered)
    expect(filtered).to receive(:sort).with(:id).and_return(sorted)

    expect(unscheduled_maintenance).to receive(:as_json).with(:only => an_instance_of(Array)).
      and_return(unscheduled_maintenance_data.reject {|k,v| :id.eql?(k)})

    resp_data = [maintenance_json('unscheduled', unscheduled_maintenance_data).
      merge(:relationships => maintenance_rel('unscheduled', unscheduled_maintenance_data))]

    get "/unscheduled_maintenances?filter=start_time%3A#{st}"
    expect(last_response).to be_ok
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data => resp_data, :links => links, :meta => meta))
  end

  it "fails when an invalid date string is passed as part of a date range" do
    expect(Flapjack::Data::UnscheduledMaintenance).to receive(:lock).
      with(no_args).
      and_yield

    st_t = fixture_time - 1_000
    ft_t = fixture_time + 4_000
    st = CGI::escape(st_t.iso8601)[0..-3]
    ft = CGI::escape(ft_t.iso8601)

    get "/unscheduled_maintenances?filter=start_time%3A#{st}..#{ft}"
    expect(last_response.status).to eq(403)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(:errors => [{
       :detail => "Invalid timestamp parameter '#{CGI::unescape(st)}..#{CGI::unescape(ft)}'",
       :status => '403'
      }]
    ))
  end

  it "ends an unscheduled maintenance period for a check" do
    expect(Flapjack::Data::UnscheduledMaintenance).to receive(:lock).
      with(no_args).
      and_yield

    end_time = Time.now + (60 * 60)

    expect(Flapjack::Data::UnscheduledMaintenance).to receive(:find_by_id!).
      with(unscheduled_maintenance.id).and_return(unscheduled_maintenance)

    expect(unscheduled_maintenance).to receive(:end_time=).with(end_time.to_i)
    expect(unscheduled_maintenance).to receive(:invalid?).and_return(false)
    expect(unscheduled_maintenance).to receive(:save!).and_return(true)

    patch "/unscheduled_maintenances/#{unscheduled_maintenance.id}",
      Flapjack.dump_json(:data => {
                           :id => unscheduled_maintenance.id,
                           :type => 'unscheduled_maintenance',
                           :attributes => {:end_time => end_time.to_i}
                         }),
      jsonapi_env
    expect(last_response.status).to eq(204)
  end

end
