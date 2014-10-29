#!/usr/bin/env ruby

# require 'sandstorm/records/redis_record'

# # NB: not yet implemented

# module Flapjack
#   module Data
#     class State

#       include Sandstorm::Records::RedisRecord

#       define_attributes :name     => :string,
#                         :is_good  => :boolean

#       unique_index_by :name
#       index_by :is_good

#       has_many :check_states, :class_name => 'Flapjack::Data::CheckState',
#         :inverse_of => :state
#       has_many :rule_drops, :class_name => 'Flapjack::Data::RuleDrop',
#         :inverse_of => :state
#       has_many :rule_routes, :class_name => 'Flapjack::Data::RuleRoute',
#         :inverse_of => :state

#       validate :name, :presence => true
#     end
#   end
# end