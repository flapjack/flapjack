#!/usr/bin/env ruby

require 'gli'
require 'logger'

# fix for webrick's assuming 1.8.7 Logger syntax
class ::Logger; alias_method :write, :<<; end

module ::GLI
  class Command
    attr_accessor :passthrough
    def _action
      @action
    end
  end

  class GLIOptionParser
    class NormalCommandOptionParser
      def parse!(parsing_result,argument_handling_strategy)
        parsed_command_options = {}
        command = parsing_result.command
        arguments = nil

        loop do
          command._action.call if command.passthrough

          option_parser_factory       = OptionParserFactory.for_command(command,@accepts)
          option_block_parser         = CommandOptionBlockParser.new(option_parser_factory, self.error_handler)
          option_block_parser.command = command
          arguments                   = parsing_result.arguments

          arguments = option_block_parser.parse!(arguments)

          parsed_command_options[command] = option_parser_factory.options_hash_with_defaults_set!
          command_finder                  = CommandFinder.new(command.commands, :default_command => command.get_default_command)
          next_command_name               = arguments.shift

          verify_required_options!(command.flags, command, parsed_command_options[command])

          begin
            command = command_finder.find_command(next_command_name)
          rescue AmbiguousCommand
            arguments.unshift(next_command_name)
            break
          rescue UnknownCommand
            arguments.unshift(next_command_name)
            # Although command finder could certainly know if it should use
            # the default command, it has no way to put the "unknown command"
            # back into the argument stack.  UGH.
            unless command.get_default_command.nil?
              command = command_finder.find_command(command.get_default_command)
            end
            break
          end
        end

        parsed_command_options[command] ||= {}
        command_options = parsed_command_options[command]

        this_command          = command.parent
        child_command_options = command_options

        while this_command.kind_of?(command.class)
          this_command_options = parsed_command_options[this_command] || {}
          child_command_options[GLI::Command::PARENT] = this_command_options
          this_command = this_command.parent
          child_command_options = this_command_options
        end

        parsing_result.command_options = command_options
        parsing_result.command = command
        parsing_result.arguments = Array(arguments.compact)

        # Lets validate the arguments now that we know for sure the command that is invoked
        verify_arguments!(parsing_result.arguments, parsing_result.command) if argument_handling_strategy == :strict

        parsing_result
      end
    end
  end
end
