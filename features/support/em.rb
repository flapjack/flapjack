#!/usr/bin/env ruby

# See http://blog.carbonfive.com/2011/02/03/raking-and-testing-with-eventmachine/

module Cucumber
  module Ast
    class TreeWalker
      alias_method :visit_features_alias, :visit_features

      def visit_features(features)
        EM.synchrony do
          visit_features_alias features
          EM.stop
        end
      end
    end
  end
end