
require 'spec_helper'
require 'flapjack/utility'

describe Flapjack::Utility do

  context "relative time ago" do

    # ported from sinatra_more tests for the method
    include Flapjack::Utility

    let(:time) { Time.new }

    before(:each) do
      expect(Time).to receive(:now).and_return(time)
    end

    it 'displays now as a minute ago' do
      expect('about a minute').to eq(relative_time_ago(time - 60))
    end
    it "displays a few minutes ago" do
      expect('4 minutes').to eq(relative_time_ago(time - (4 * 60)))
    end
    it "displays an hour ago" do
      expect('about 1 hour').to eq(relative_time_ago(time - (65 * 60)))
    end
    it "displays a few hours ago" do
      expect('about 3 hours').to eq(relative_time_ago(time - (185 * 60)))
    end
    it "displays a day ago" do
      expect('1 day').to eq(relative_time_ago(time - (24 * 60 * 60)))
    end
    it "displays about 2 days ago" do
      expect('about 2 days').to eq(relative_time_ago(time - (2 * 24 * 60 * 60) + (5 * 60)))
    end
    it "displays a few days ago" do
      expect('5 days').to eq(relative_time_ago(time - (5 * 24 * 60 * 60) - (5 * 60)))
    end
    it "displays a month ago" do
      expect('about 1 month').to eq(relative_time_ago(time - (32 * 24 * 60 * 60) - (5 * 60)))
    end
    it "displays a few months ago" do
      expect('6 months').to eq(relative_time_ago(time - (180 * 24 * 60 * 60) - (5 * 60)))
    end
    it "displays a year ago" do
      expect('about 1 year').to eq(relative_time_ago(time - (365 * 24 * 60 * 60) - (5 * 60)))
    end
    it "displays a few years ago" do
      expect('over 7 years').to eq(relative_time_ago(time - (2800 * 24 * 60 * 60) + (5 * 60)))
    end

  end

end

