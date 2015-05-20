require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::Reports', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:check) { double(Flapjack::Data::Check, :id => check_data[:id]) }
  let(:tag)   { double(Flapjack::Data::Tag, :id => tag_data[:name]) }

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

  def expect_checks(path, report_type, opts = {})
    link_opts = {}
    expect(Flapjack::Data::Report).to receive(report_type).
      with(check, :start_time => opts[:start], :end_time => opts[:finish]).
      and_return(:type => "#{report_type}_report")
    link_opts[:start_time] = opts[:start].iso8601 unless opts[:start].nil?
    link_opts[:end_time] = opts[:finish].iso8601 unless opts[:finish].nil?

    one_lnk = opts[:one] ? "/#{check.id}" : ''
    report_data = {
      :type => "#{report_type}_report"
    }

    result = {
      :data => (opts[:one] ? report_data : [report_data])
    }

    links_data = {:self  => "http://example.org/#{report_type}_reports/checks#{one_lnk}"}
    unless link_opts.empty?
      links_data[:self] += "?#{link_opts.to_query}"
    end

    if opts[:all]
      page = double('page', :all => [check])
      sorted = double('sorted')
      expect(sorted).to receive(:page).with(1, :per_page => 20).
        and_return(page)

      expect(sorted).to receive(:count).and_return(1)

      expect(Flapjack::Data::Check).to receive(:sort).
        with(:id).and_return(sorted)

      page_opts = link_opts.merge(:page => 1)
      links_data.update(
        :first => "http://example.org/#{report_type}_reports/checks?#{page_opts.to_query}",
        :last  => "http://example.org/#{report_type}_reports/checks?#{page_opts.to_query}"
      )
      result.update(:meta => meta)
    elsif opts[:one]
      expect(Flapjack::Data::Check).to receive(:find_by_id!).
        with(check.id).and_return(check)
    end

    result.update(:links => links_data)

    par = (opts[:start] && opts[:finish]) ?
      {:start_time => opts[:start].iso8601, :end_time => opts[:finish].iso8601} : {}

    get path, par
    expect(last_response).to be_ok
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(result))
  end

  def expect_tag_checks(path, report_type, opts = {})
    link_opts = {}
    expect(Flapjack::Data::Report).to receive(report_type).
      with(check, :start_time => opts[:start], :end_time => opts[:finish]).
      and_return(:type => "#{report_type}_report")
    link_opts[:start_time] = opts[:start].iso8601 unless opts[:start].nil?
    link_opts[:end_time] = opts[:finish].iso8601 unless opts[:start].nil?

    checks = double('checks')
    expect(tag).to receive(:checks).and_return(checks)
    expect(Flapjack::Data::Tag).to receive(:find_by_id!).
      with(tag.id).and_return(tag)

    page = double('page', :all => [check])
    sorted = double('sorted')
    expect(sorted).to receive(:page).with(1, :per_page => 20).
      and_return(page)
    expect(sorted).to receive(:count).and_return(1)
    expect(checks).to receive(:sort).
      with(:id).and_return(sorted)

    page_opts = link_opts.merge(:page => 1)
    links_data = {
      :self  => "http://example.org/#{report_type}_reports/tags/#{tag.id}",
      :first => "http://example.org/#{report_type}_reports/tags/#{tag.id}?#{page_opts.to_query}",
      :last  => "http://example.org/#{report_type}_reports/tags/#{tag.id}?#{page_opts.to_query}"
    }

    unless link_opts.empty?
      links_data[:self] += "?#{link_opts.to_query}"
    end

    result = {
      :links => links_data,
      :data => [
        {:type => "#{report_type}_report"}
      ],
      :meta => meta
    }

    par = opts[:start] && opts[:finish] ?
      {:start_time => opts[:start].iso8601, :end_time => opts[:finish].iso8601} : {}

    get path, par
    expect(last_response).to be_ok
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(result))
  end

  [:outage, :downtime].each do |report_type|

    let(:start)  { Time.parse('1 Jan 2012') }
    let(:finish) { Time.parse('6 Jan 2012') }

    it "returns a #{report_type} report for all checks" do
      expect_checks("/#{report_type}_reports/checks", report_type, :all => true)
    end

    it "returns a #{report_type} report for a check" do
      expect_checks("/#{report_type}_reports/checks/#{check.id}", report_type, :one => true)
    end

    it "returns a #{report_type} report for all checks linked to a tag" do
      expect_tag_checks("/#{report_type}_reports/tags/#{tag.id}", report_type)
    end

    it "doesn't return a #{report_type} report for a check that's not found" do
      expect(Flapjack::Data::Check).to receive(:find_by_id!).
        with(check.id).
        and_raise(Zermelo::Records::Errors::RecordNotFound.new(Flapjack::Data::Check, check.id))

      get "/#{report_type}_reports/checks/#{check.id}"
      expect(last_response).to be_not_found
    end

    it "doesn't return a #{report_type} report for checks linked to a tag that's not found" do
      expect(Flapjack::Data::Tag).to receive(:find_by_id!).
        with(tag.id).
        and_raise(Zermelo::Records::Errors::RecordNotFound.new(Flapjack::Data::Tag, tag.id))

      get "/#{report_type}_reports/tags/#{tag.id}"
      expect(last_response).to be_not_found
    end

    it "returns a #{report_type} report for all checks within a time window" do
      expect_checks("/#{report_type}_reports/checks", report_type, :all => true,
        :start => start, :finish => finish)
    end

    it "returns a #{report_type} report for a check within a time window" do
      expect_checks("/#{report_type}_reports/checks/#{check.id}", report_type,
        :one => true, :start => start, :finish => finish)
    end

    it "returns a #{report_type} report for all checks linked to a tag" do
      expect_tag_checks("/#{report_type}_reports/tags/#{tag.id}", report_type,
        :start => start, :finish => finish)
    end
  end
end
