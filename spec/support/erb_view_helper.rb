require 'flapjack/utility'

module ErbViewHelper

  TEMPLATE_PATH = File.dirname(__FILE__) +
      '/../../lib/flapjack/gateways/web/views/'

  include Flapjack::Utility

  def render_erb(file, bind)
    erb = ERB.new(File.read(TEMPLATE_PATH + file))
    erb.result(bind)
  end

  def h(text)
    ERB::Util.h(text)
  end

  def u(text)
    ERB::Util.u(text)
  end

end