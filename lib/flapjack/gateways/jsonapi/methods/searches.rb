#!/usr/bin/env ruby

# require 'sinatra/base'

# require 'flapjack/data/contact'
# require 'flapjack/data/check'
# require 'flapjack/data/tag'

# module Flapjack
#   module Gateways
#     class JSONAPI < Sinatra::Base
#       module Methods
#         module Searches

#           # TODO probably replace with 'filter' arguments on the GETs of the resources themselves

#           def self.registered(app)
#             app.helpers Flapjack::Gateways::JSONAPI::Helpers::Headers
#             app.helpers Flapjack::Gateways::JSONAPI::Helpers::Miscellaneous
#             app.helpers Flapjack::Gateways::JSONAPI::Helpers::Resources

#             app.get %r{^/search/(contacts|checks|tags)$} do

#               resource = params[:captures][0]

#               klass, string_params, boolean_params = case resource
#               when 'contacts'
#                 [Flapjack::Data::Contact, [:id, :name], []]
#               when 'checks'
#                 [Flapjack::Data::Check, [:id, :name, :state, :ack_hash], [:enabled]]
#               when 'tags'
#                 [Flapjack::Data::Tag, [:id, :name], []]
#               end

#               opts = string_params.each_with_object({}) do |sp, memo|
#                 next unless params.has_key?(sp.to_s)
#                 memo[sp] = Regexp.new(params[sp.to_s])
#               end

#               bool_opts = boolean_params.each_with_object({}) do |sp, memo|
#                 next unless params.has_key?(sp.to_s)
#                 memo[sp] = case params[sp.to_s].downcase
#                 when '0', 'f', 'false', 'n', 'no'
#                   false
#                 when '1', 't', 'true', 'y', 'yes'
#                   true
#                 else
#                   nil
#                 end
#               end

#               opts.update(bool_opts)

#               records, meta = paginate_get(klass.intersect(opts).sort(:name),
#                 :total => klass.intersect(opts).count, :page => params[:page],
#                 :per_page => params[:per_page])

#               records_as_json = klass.as_jsonapi(*records)

#               json_data = {}
#               json_data.update(resource.to_sym => records_as_json)
#               json_data.update(:meta => meta) unless meta.nil? || meta.empty?
#               Flapjack.dump_json(json_data)
#             end
#           end
#         end
#       end
#     end
#   end
# end
