require 'spec_helper'

describe 'web/views/contact.html.erb', :erb_view => true do

  it "should escape unsafe check characters in URI parameters" do
    @contact = double('contact')

    expect(@contact).to receive(:name).twice.and_return('Aeschylus')

    no_notification_rules = double('no_notification_rules', :all => [])
    expect(@contact).to receive(:notification_rules).and_return(no_notification_rules)

    @contact_media = []

    check = double('check')
    expect(check).to receive(:name).exactly(3).times.and_return('Disk / Utilisation')
    checks_all = double('all_checks', :all => [check])

    entity = double('entity')
    expect(entity).to receive(:name).exactly(3).times.and_return('abc-xyz-01')
    expect(entity).to receive(:checks).and_return(checks_all)

    all_entities = double('all_entities', :all => [entity])
    expect(@contact).to receive(:entities).and_return(all_entities)

    page = render_erb('contact.html.erb', binding)
    expect(page).to match(%r{\?entity=abc-xyz-01&amp;check=Disk%20%2F%20Utilisation})
  end

end
