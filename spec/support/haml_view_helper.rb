require 'haml'
require 'flapjack/utility'

module HamlViewHelper

  TEMPLATE_PATH = File.dirname(__FILE__) +
      '/../../lib/flapjack/gateways/web/views/'

  include Flapjack::Utility

  def render_haml(file, scope)
    Haml::Engine.new(File.read(TEMPLATE_PATH + file)).render(scope)
  end

end