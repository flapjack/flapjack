#!/usr/bin/env ruby

# require 'sandstorm/records/redis_record'

# # NB: not yet implemented

# module Flapjack
#   module Data
#     class Path

#       include Sandstorm::Records::RedisRecord

#       define_attributes :alerting => :boolean

#       index_by :alerting

#       belongs_to :route, :class_name => 'Flapjack::Data::Route',
#         :inverse_of => :paths

#       has_and_belongs_to_many :checks, :class_name => 'Flapjack::Data::Check',
#         :inverse_of => :paths

#       validate :alerting, :presence => true

#     end
#   end
# end