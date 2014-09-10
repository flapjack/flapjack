require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::ReportMethods', :sinatra => true, :logger => true do

  include_context "jsonapi"

  let(:entity)   { double(Flapjack::Data::Entity, :id => '333') }
  let(:check)    { double(Flapjack::Data::Check, :id => '666') }

  let(:check_presenter) { double(Flapjack::Gateways::JSONAPI::CheckPresenter) }

  let(:report_data) { {'report' => 'data'}}

  def result_data(report_type)
    {
      report_type => [
        report_data.merge(
        :links => {
          :entity => [entity.id],
          :check  => [check.id]
        })],
      :linked => {
        :entities => [{'entity' => 'json'}],
        :checks => [{'check' => 'json'}]
      }
     }
  end

  def expect_entities(path, report_type, opts = {})
    if opts[:start] && opts[:finish]
      expect(check_presenter).to receive(report_type).
        with(opts[:start].to_i, opts[:finish].to_i).
        and_return(report_data)
    else
      expect(check_presenter).to receive(report_type).and_return(report_data)
    end

    expect(Flapjack::Gateways::JSONAPI::CheckPresenter).to receive(:new).
      with(check).and_return(check_presenter)

    entity_checks = double('entity_checks', :all => [check])
    expect(entity).to receive(:checks).and_return(entity_checks)

    if opts[:all]
      expect(Flapjack::Data::Entity).to receive(:all).and_return([entity])
    elsif opts[:some]
      expect(Flapjack::Data::Entity).to receive(:find_by_ids!).
        with(entity.id).and_return([entity])
    end

    expect(Flapjack::Data::Entity).to receive(:associated_ids_for_checks).
      with([entity.id]).and_return({entity.id => [check.id]})
    expect(Flapjack::Data::Check).to receive(:associated_ids_for_entity).
      with([check.id]).and_return({check.id => entity.id})

    expect(entity).to receive(:as_json).and_return({'entity' => 'json'})
    expect(check).to receive(:as_json).and_return({'check' => 'json'})

    result = result_data("#{report_type}_reports")

    par = opts[:start] && opts[:finish] ?
      {:start_time => opts[:start].iso8601, :end_time => opts[:finish].iso8601} : {}

    get path, par
    expect(last_response).to be_ok
    expect(last_response.body).to eq(result.to_json)
  end

  def expect_checks(path, report_type, opts = {})
    if opts[:start] && opts[:finish]
      expect(check_presenter).to receive(report_type).
        with(opts[:start].to_i, opts[:finish].to_i).
        and_return(report_data)
    else
      expect(check_presenter).to receive(report_type).and_return(report_data)
    end

    expect(Flapjack::Gateways::JSONAPI::CheckPresenter).to receive(:new).
      with(check).and_return(check_presenter)

    if opts[:all]
      expect(Flapjack::Data::Check).to receive(:all).and_return([check])
    elsif opts[:some]
      expect(Flapjack::Data::Check).to receive(:find_by_ids!).
        with(check.id).and_return([check])
    end

    expect(check).to receive(:entity).and_return(entity)
    expect(Flapjack::Data::Entity).to receive(:associated_ids_for_checks).
      with([entity.id]).and_return({entity.id => [check.id]})
    expect(Flapjack::Data::Check).to receive(:associated_ids_for_entity).
      with([check.id]).and_return({check.id => entity.id})

    expect(entity).to receive(:as_json).and_return({'entity' => 'json'})
    expect(check).to receive(:as_json).and_return({'check' => 'json'})

    result = result_data("#{report_type}_reports")

    par = opts[:start] && opts[:finish] ?
      {:start_time => opts[:start].iso8601, :end_time => opts[:finish].iso8601} : {}

    get path, par
    expect(last_response).to be_ok
    expect(last_response.body).to eq(result.to_json)
  end

  [:status, :scheduled_maintenance, :unscheduled_maintenance, :outage,
   :downtime].each do |report_type|

    it "returns a #{report_type} report for all entities" do
      expect_entities("/#{report_type}_report/entities", report_type, :all => true)
    end

    it "returns a #{report_type} report for some entities" do
      expect_entities("/#{report_type}_report/entities/#{entity.id}", report_type, :some => true)
    end

    it "doesn't return a #{report_type} report for an entity that's not found" do
      expect(Flapjack::Data::Entity).to receive(:find_by_ids!).
        with(entity.id).
        and_raise(Sandstorm::Records::Errors::RecordsNotFound.new(Flapjack::Data::Entity, [entity.id]))

      get "/#{report_type}_report/entities/#{entity.id}"
      expect(last_response.status).to eq(404)
    end

    it "returns a #{report_type} report for all checks" do
      expect_checks("/#{report_type}_report/checks", report_type, :all => true)
    end

    it "returns a #{report_type} report for some checks" do
      expect_checks("/#{report_type}_report/checks/#{check.id}", report_type, :some => true)
    end

    it "doesn't return a #{report_type} report for a check that's not found" do
      expect(Flapjack::Data::Check).to receive(:find_by_ids!).
        with(check.id).
        and_raise(Sandstorm::Records::Errors::RecordsNotFound.new(Flapjack::Data::Check, [check.id]))

      get "/#{report_type}_report/checks/#{check.id}"
      expect(last_response).to be_not_found
    end

    unless :status.eql?(report_type)

      let(:start)  { Time.parse('1 Jan 2012') }
      let(:finish) { Time.parse('6 Jan 2012') }

      it "returns a #{report_type} report for all entities within a time window" do
        expect_entities("/#{report_type}_report/entities", report_type, :all => true,
          :start => start, :finish => finish)
      end

      it "returns a #{report_type} report for some entities within a time window" do
        expect_entities("/#{report_type}_report/entities/#{entity.id}", report_type, :some => true,
          :start => start, :finish => finish)
      end

      it "returns a #{report_type} report for all checks within a time window" do
        expect_checks("/#{report_type}_report/checks", report_type, :all => true,
          :start => start, :finish => finish)
      end

      it "returns a #{report_type} report for some checks within a time window" do
        expect_checks("/#{report_type}_report/checks/#{check.id}", report_type, :some => true,
          :start => start, :finish => finish)
      end

    end

  end
end
