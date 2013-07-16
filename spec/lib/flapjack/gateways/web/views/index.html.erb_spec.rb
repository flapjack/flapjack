require 'spec_helper'

describe 'web/views/checks.html.erb', :erb_view => true do

  it "should escape unsafe check characters in URI parameters" do
    @states = {'abc-xyz-01' => [['Disk / Utilisation', 'OK', 'Looking good', '-', '-', false, false, nil, nil]]}
    @entities_sorted = ['abc-xyz-01']
    @adjective = "all"

    page = render_erb('checks.html.erb', binding)
    page.should match(%r{\?entity=abc-xyz-01&amp;check=Disk%20%2F%20Utilisation})
  end

end
