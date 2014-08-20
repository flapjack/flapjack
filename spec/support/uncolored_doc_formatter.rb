require 'rspec/core/formatters/base_text_formatter'

module NoColorizer
  def self.wrap(text, color)
    text
  end
end

class UncoloredDocFormatter < RSpec::Core::Formatters::BaseTextFormatter
  RSpec::Core::Formatters.register self, :example_group_started, :example_group_finished,
                                         :example_passed, :example_pending, :example_failed,
                                         :dump_failures, :dump_pending, :dump_summary

  def initialize(output)
    super
    @group_level = 0
  end

  def example_group_started(notification)
    output.puts if @group_level == 0
    output.puts "#{current_indentation}#{notification.group.description.strip}"

    @group_level += 1
  end

  def example_group_finished(notification)
    @group_level -= 1
  end

  def example_passed(passed)
    output.puts "#{current_indentation}#{passed.example.description.strip}"
  end

  def example_pending(pending)
    output.puts "#{current_indentation}#{pending.example.description.strip} (PENDING: #{pending.example.execution_result.pending_message})"
  end

  def example_failed(failure)
    output.puts "#{current_indentation}#{failure.example.description.strip} (FAILED - #{next_failure_index})"
  end

  def dump_failures(notification)
    return if notification.failure_notifications.empty?
    output.puts notification.fully_formatted_failed_examples(NoColorizer)
  end

  def dump_pending(notification)
    return if notification.pending_examples.empty?
    output.puts notification.fully_formatted_pending_examples(NoColorizer)
  end

  def dump_summary(notification)
    output.puts notification.fully_formatted(NoColorizer)
  end

private

  def next_failure_index
    @next_failure_index ||= 0
    @next_failure_index += 1
  end

  def current_indentation
    '  ' * @group_level
  end

  def example_group_chain
    example_group.parent_groups.reverse
  end

end