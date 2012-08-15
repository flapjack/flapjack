require 'rspec/core/formatters/documentation_formatter'

class UncoloredDocFormatter < RSpec::Core::Formatters::DocumentationFormatter

  def color(text, color_code)
    text
  end

end