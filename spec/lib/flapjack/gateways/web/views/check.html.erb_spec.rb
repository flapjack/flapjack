require 'spec_helper'

describe 'web/views/check.html.erb', :erb_view => true do

  it "should escape unsafe check characters in URIs" do
    @base_url = 'http://www.example.com/flapjack/'

    @entity_name = 'abc-xyz-01'
    @check_name  = 'Disk / Utilisation'
    @last_notifications = {}

    @current_time = Time.now

    page = render_erb('check.html.erb', binding)
    expect(page).to match(%r{/abc-xyz-01/Disk%20%2F%20Utilisation})
  end

end
