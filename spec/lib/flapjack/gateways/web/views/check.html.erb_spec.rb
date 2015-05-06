require 'spec_helper'
require 'chronic_duration'

describe 'web/views/check.html.erb', :erb_view => true do

  it "should escape unsafe check characters in URIs" do
    @base_url = 'http://www.example.com/flapjack/'

    @entity = 'abc-xyz-01'
    @check  = 'Disk / Utilisation'
    @last_notifications = {}
    @check_initial_failure_delay = 30
    @check_repeat_failure_delay  = 60
    @check_initial_failure_delay_is_default = true
    @check_repeat_failure_delay_is_default  = true

    page = render_erb('check.html.erb', binding)
    expect(page).to match(%r{/abc-xyz-01/Disk%20%2F%20Utilisation})
  end

end
