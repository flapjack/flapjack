#!/usr/bin/env ruby

require 'thin'
require 'redis'

# we don't want to stop the entire EM reactor when we stop a web server
# & @connections data type changed in thin 1.5.1
module Thin

  # see https://github.com/flapjack/flapjack/issues/169
  class Request
    class EqlTempfile < ::Tempfile
      def eql?(obj)
        obj.equal?(self) && (obj == self)
      end
    end

    def move_body_to_tempfile
      current_body = @body
      current_body.rewind
      @body = Thin::Request::EqlTempfile.new(BODY_TMPFILE)
      @body.binmode
      @body << current_body.read
      @env[RACK_INPUT] = @body
    end
  end

  module Backends
    class Base
      def stop!
        @running  = false
        @stopping = false

        # EventMachine.stop if EventMachine.reactor_running?

        case @connections
        when Array
          @connections.each { |connection| connection.close_connection }
        when Hash
          @connections.each_value { |connection| connection.close_connection }
        end
        close
      end
    end
  end
end

# As Redis::Future objects inherit from BasicObject, it's difficult to
# distinguish between them and other objects in collected data from
# pipelined queries.
#
# (One alternative would be to put other values in Futures ourselves, and
#  evaluate everything...)
class Redis
  class Future
    def class
      ::Redis::Future
    end
  end
end

module GLI
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
          command_finder                  = CommandFinder.new(command.commands,command.get_default_command)
          next_command_name               = arguments.shift

          gli_major_version, gli_minor_version = GLI::VERSION.split('.')
          required_options = [command.flags, parsing_result.command, parsed_command_options[command]]
          verify_required_options!(*required_options)

          begin
            command = command_finder.find_command(next_command_name)
          rescue AmbiguousCommand
            arguments.unshift(next_command_name)
            break
          rescue UnknownCommand
            arguments.unshift(next_command_name)
            # Although command finder could certainy know if it should use
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
