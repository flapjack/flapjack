require 'rspec/core/formatters/base_formatter'

class ProfileAllFormatter < RSpec::Core::Formatters::BaseFormatter

  def initialize(output)
    super(output)
    @example_times = []
  end

  def start(count)
    super(count)
    @output.puts "Profiling enabled."
  end

  def example_started(example)
    super(example)
    @time = ((Time.respond_to?(:zone) && Time.zone) ? Time.zone.now : Time.now)
  end

  def example_passed(example)
    @example_times << [
      example_group.description,
      example.description,
      ((Time.respond_to?(:zone) && Time.zone) ? Time.zone.now : Time.now) - @time
    ]
    super(example)
  end

  def start_dump
    super
    @output.puts "\n\nExample times:\n"

    @example_times = @example_times.sort_by do |description, example, time|
      time
    end.reverse

    @example_times.each do |description, example, time|
      @output.print sprintf("%.7f", time)
      @output.puts " #{description} #{example}"
    end
    @output.flush
  end

end