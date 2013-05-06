require 'spec_helper'

describe 'web/views/contact.haml', :haml_view => true do

  it "should escape unsafe check characters in URI parameters" do
    @contact = mock('contact')
    @contact.should_receive(:media)
    @contact.should_receive(:name).twice.and_return('Aeschylus')
    @contact.should_receive(:notification_rules)

    entity = mock('entity')
    entity.should_receive(:name).exactly(3).times.and_return('abc-xyz-01')

    checks = ['Disk / Utilisation']

    @entities_and_checks = [{:entity => entity, :checks => checks}]

    page = render_haml('contact.haml', self)
    page.should match(%r{\?entity=abc-xyz-01&amp;check=Disk\+%2F\+Utilisation})
  end

end
