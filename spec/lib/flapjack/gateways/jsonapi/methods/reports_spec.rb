require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::Reports', :sinatra => true, :logger => true, :pact_fixture => true do

  before do
    skip "broken"
  end

  include_context "jsonapi"

  let(:check)    { double(Flapjack::Data::Check, :id => check_data[:id]) }

  let(:check_presenter) { double(Flapjack::Gateways::JSONAPI::Helpers::CheckPresenter) }

  let(:report_data) { {'report' => 'data'}}

  let(:meta) {
    {
      :pagination => {
        :page        => 1,
        :per_page    => 20,
        :total_pages => 1,
        :total_count => 1
      }
    }
  }

  def result_data(report_type, opts = {})
    rd = report_data.merge(:links => {:check  => check.id})
    rd = [rd] unless opts[:one].is_a?(TrueClass)
    {report_type => rd}
  end

  def links_data(report_type)
    {
      :self  => "http://example.org/#{report_type}_reports",
      :first => "http://example.org/#{report_type}_reports?page=1",
      :last  => "http://example.org/#{report_type}_reports?page=1"
    }
  end

  def expect_checks(path, report_type, action_pres, opts = {})
    if opts[:start] && opts[:finish]
      expect(check_presenter).to receive(action_pres).
        with(opts[:start].to_i, opts[:finish].to_i).
        and_return(report_data)
    else
      expect(check_presenter).to receive(action_pres).and_return(report_data)
    end

    expect(Flapjack::Gateways::JSONAPI::Helpers::CheckPresenter).to receive(:new).
      with(check).and_return(check_presenter)

    if opts[:all]
      expect(Flapjack::Data::Check).to receive(:count).and_return(1)

    page = double('page', :all => [check])
      sorted = double('sorted')
      expect(sorted).to receive(:page).with(1, :per_page => 20).
        and_return(page)
      expect(Flapjack::Data::Check).to receive(:sort).
        with(:name).and_return(sorted)
    elsif opts[:one]
      expect(Flapjack::Data::Check).to receive(:find_by_ids!).
        with(check.id).and_return([check])
    end

    result = result_data("#{report_type}_reports", :one => opts[:one])

    if opts[:all]
      result.update(:links => links_data(report_type), :meta => meta)
    end

    if report_type.to_s == 'outage' && opts[:all]
      p result
    end

    par = opts[:start] && opts[:finish] ?
      {:start_time => opts[:start].iso8601, :end_time => opts[:finish].iso8601} : {}

    get path, par
    expect(last_response).to be_ok

    if report_type.to_s == 'outage' && opts[:all]
      p last_response.body
    end

    expect(last_response.body).to be_json_eql(Flapjack.dump_json(result))
  end

  [:status, :scheduled_maintenance, :unscheduled_maintenance, :outage,
   :downtime].each do |report_type|

    action_pres = case report_type
    when :status, :downtime
      report_type
    else
      "#{report_type}s"
    end

    it "returns a #{report_type} report for all checks" do
      expect_checks("/#{report_type}_reports", report_type, action_pres, :all => true)
    end

    it "returns a #{report_type} report for some checks" do
      expect_checks("/#{report_type}_reports/#{check.id}", report_type, action_pres, :one => true)
    end

    it "doesn't return a #{report_type} report for a check that's not found" do
      expect(Flapjack::Data::Check).to receive(:find_by_ids!).
        with(check.id).
        and_raise(Zermelo::Records::Errors::RecordsNotFound.new(Flapjack::Data::Check, [check.id]))

      get "/#{report_type}_reports/#{check.id}"
      expect(last_response).to be_not_found
    end

    unless :status.eql?(report_type)

      let(:start)  { Time.parse('1 Jan 2012') }
      let(:finish) { Time.parse('6 Jan 2012') }

      it "returns a #{report_type} report for all checks within a time window" do
        expect_checks("/#{report_type}_reports", report_type, action_pres, :all => true,
          :start => start, :finish => finish)
      end

      it "returns a #{report_type} report for a check within a time window" do
        expect_checks("/#{report_type}_reports/#{check.id}", report_type,
          action_pres, :one => true, :start => start, :finish => finish)
      end

    end

  end
end
