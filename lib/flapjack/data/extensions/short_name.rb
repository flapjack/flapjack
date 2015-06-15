#!/usr/bin/env ruby

require 'securerandom'

require 'active_support/concern'

require 'swagger/blocks'

module Flapjack
  module Data
    module Extensions
      module ShortName
        extend ActiveSupport::Concern

        module ClassMethods

          def short_model_name
            ActiveModel::Name.new(self, Flapjack::Data, self.name.demodulize)
          end

        end
      end
    end
  end
end
