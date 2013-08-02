require 'spec_helper'

describe 'web/views/check.html.erb', :erb_view => true do

  it "should escape unsafe check characters in URIs" do
    @entity = 'abc-xyz-01'
    @check  = 'Disk / Utilisation'
    @last_notifications = {}

    page = render_erb('check.html.erb', binding)
    page.should match(%r{/abc-xyz-01/Disk%20%2F%20Utilisation})
  end

end
