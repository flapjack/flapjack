require 'spec_helper'

describe 'web/views/checks.haml', :haml_view => true do

  it "should escape unsafe check characters in URI parameters" do
    @states = [['abc-xyz-01', 'Disk / Utilisation', '-', '-', '-', false, false, nil, nil]]
    @adjective = "all"

    page = render_haml('checks.haml', self)
    page.should match(%r{\?entity=abc-xyz-01&amp;check=Disk\+%2F\+Utilisation})
  end

end
