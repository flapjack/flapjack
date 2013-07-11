require 'spec_helper'

describe 'web/views/contact.html.erb', :erb_view => true do

  it "should escape unsafe check characters in URI parameters" do
    @contact = mock('contact')
    @contact.should_receive(:media)
    @contact.should_receive(:name).twice.and_return('Aeschylus')
    @contact.should_receive(:notification_rules)

    entity = mock('entity')
    entity.should_receive(:name).exactly(3).times.and_return('abc-xyz-01')

    checks = ['Disk / Utilisation']

    @entities_and_checks = [{:entity => entity, :checks => checks}]

    page = render_erb('contact.html.erb', binding)
    page.should match(%r{\?entity=abc-xyz-01&amp;check=Disk%20%2F%20Utilisation})
  end

end
