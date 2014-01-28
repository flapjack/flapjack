require 'spec_helper'

describe 'web/views/contact.html.erb', :erb_view => true do

  it "should escape unsafe check characters in URI parameters" do
    @contact = double('contact')
    expect(@contact).to receive(:media)
    expect(@contact).to receive(:name).and_return('Aeschylus')
    expect(@contact).to receive(:notification_rules)

    entity = double('entity')
    expect(entity).to receive(:name).exactly(3).times.and_return('abc-xyz-01')

    checks = ['Disk / Utilisation']

    @entities_and_checks = [{:entity => entity, :checks => checks}]

    page = render_erb('contact.html.erb', binding)
    expect(page).to match(%r{\?entity=abc-xyz-01&amp;check=Disk%20%2F%20Utilisation})
  end

end
