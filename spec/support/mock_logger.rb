class MockLogger
  attr_accessor :messages, :errors

  def initialize
    @messages = []
    @errors   = []
  end

  %w(debug info warn).each do |level|
    class_eval <<-RUBY
      def #{level}(msg = nil, &block)
        msg = yield if msg.nil? && block_given?
        @messages << '#{level.upcase}' + ': ' + msg
      end
    RUBY
  end

  %w(error fatal).each do |level|
    class_eval <<-ERRORS
      def #{level}(msg = nil, &block)
        msg = yield if msg.nil? && block_given?
        @messages << '#{level.upcase}' + ': ' + msg
        @errors   << '#{level.upcase}' + ': ' + msg
      end
    ERRORS
  end

  %w(debug info warn error fatal).each do |level|
    class_eval <<-LEVELS
      def #{level}?
        true
      end
    LEVELS
  end

end