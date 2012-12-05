require 'spec_helper'

describe 'web/views/check.haml', :haml_view => true do

  it "should escape unsafe check characters in URIs" do
    @entity = 'abc-xyz-01'
    @check  = 'Disk / Utilisation'
    @last_notifications = {}

    page = render_haml('check.haml', self)
    page.should match(%r{/abc-xyz-01/Disk%20%2F%20Utilisation})
  end

end
