#!/usr/bin/env ruby

require 'sinatra/base'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Helpers
        module Serialiser

          def as_jsonapi(klass, resources, resources_ids, options = {})
            included = options[:include]
            fields   = options[:fields]
            query_type = options[:query_type]

            payload = {}

            unless included.nil? || included.empty?
              payload = collect_included_data(klass, resources,
                :include => included, :query_type => query_type)
            end

            ret = {
              :data => as_jsonapi_data(klass, resources, resources_ids,
                :primary => true, :payload => payload, :fields => fields,
                :unwrap => options[:unwrap])
            }
            unless payload.nil? || payload.empty?
              ret[:included] = included_data_from_payload(payload, :fields => fields)
            end
            ret
          end

          def as_jsonapi_included(klass, resources, options = {})
            included = options[:include]
            fields   = options[:fields]

            payload = collect_included_data(klass, resources,
              :include => included, :query_type => :association)

            included_data_from_payload(payload, :fields => fields)
          end

          def as_jsonapi_data(klass, resources, resources_ids, options = {})
            unwrap  = options[:unwrap]
            payload = options[:payload]

            relationship_scopes = options[:relationship_scopes]

            fields = extract_fields(options[:fields], klass)

            whitelist = if klass.respond_to?(:jsonapi_methods)
              method_def = klass.jsonapi_methods[:get] || klass.jsonapi_methods[:post]
              method_def.nil? ? [] : method_def.attributes
            else
              []
            end

            jsonapi_fields = if fields.nil?
              whitelist
            else
              Set.new(fields).keep_if {|f| whitelist.include?(f) }.to_a
            end

            links = jsonapi_linkages(klass, resources_ids, :primary => options[:primary],
              :payload => payload, :relationship_scopes => relationship_scopes)

            resources_as_json = resources.collect do |r|
              r_id = r.id

              l = links[r_id]

              data = {
                :type => klass.short_model_name.singular,
                :id => r_id
              }
              attrs = r.as_json(:only => jsonapi_fields)
              data[:attributes] = attrs unless attrs.empty?
              data[:relationships] = l unless l.nil? || l.empty?
              data
            end

            unless (resources_as_json.size == 1) && unwrap.is_a?(TrueClass)
              return resources_as_json
            end

            resources_as_json.first
          end

          def lock_for_include_clause(klass, options = {})
            included = options[:include]

            locks = Set.new

            included_parts = included.map {|i| i.split('.')}.sort_by(&:length)

            included_parts.each do |incl_fragments|
              incl_todo = incl_fragments
              incl_done = []

              last_klass = klass

              until incl_todo.empty?
                fragment = incl_todo.shift
                last_klass, lock_k = resolve_include_locks(last_klass, fragment)
                incl_done.push(fragment)
                locks |= lock_k
              end
            end

            locks.to_a
          end

          def resolve_include_locks(parent_klass, name)
            links = if parent_klass.respond_to?(:jsonapi_associations)
              parent_klass.jsonapi_associations || {}
            else
              {}
            end

            assoc_data = links[name.to_sym]

            return if assoc_data.nil? || !assoc_data.link

            klass = assoc_data.data_klass

            [klass, assoc_data.lock_klasses]
          end

          def collect_included_data(klass, resources, options = {})
            included = options[:include]
            query_type = options[:query_type]

            payload = {}

            init_node = [klass, nil => resources.ids]

            included_parts = included.map {|i| i.split('.')}.sort_by(&:length)

            included_parts.each do |incl_fragments|
              incl_todo = incl_fragments
              incl_done = []

              last_node = init_node

              until incl_todo.empty?
                fragment = incl_todo.shift

                last_node = resolve_include_fragment(last_node, fragment,
                  incl_todo, incl_done, :query_type => query_type)
                incl_done.push(fragment)

                # store new klass, resources as appropriate by joined incl_done
                k = incl_done.join(".")

                payload[k] ||= [last_node.first]
                payload[k] << last_node.last
              end
            end

            payload
          end

          def resolve_include_fragment(node, name, incl_todo, incl_done,
            options = {})

            query_type = options[:query_type]

            parent_klass = node.first
            nlv = node.last.values
            parent_resources = if nlv.all? {|v| v.is_a?(Set) || v.is_a?(Array)}
              nlv.reduce(Set.new, :|)
            else
              nlv
            end

            parent_links = if parent_klass.respond_to?(:jsonapi_associations)
              parent_klass.jsonapi_associations || {}
            else
              {}
            end

            assoc_data = parent_links[name.to_sym]

            return [] if assoc_data.nil? ||
              (:resource.eql?(query_type) && !assoc_data.includable) ||
              (:association.eql?(query_type) && !assoc_data.link)

            fragment_klass = assoc_data.data_klass

            # NB: if anything's limiting the returned data, it would need
            # to be included here
            scope = parent_klass.intersect(:id => parent_resources)

            data = if assoc_data.association_data.nil?
              scope.all.each_with_object({}) do |r, memo|
                d = r.send(name.to_sym)
                memo[r.id] = case d
                when nil
                  nil
                when Zermelo::Filter, Zermelo::Associations::Multiple
                  d.ids
                when Array, Set
                  d.map(&:id)
                else
                  d.id
                end
              end
            else
              scope.associated_ids_for(name.to_sym)
            end

            [fragment_klass, data]
          end

          def included_data_from_payload(payload, options = {})
            fields = options[:fields]

            scopes_by_klass = {}
            names_by_klass  = {}

            payload.each do |name, pl|
              local_klass = pl.first

              scopes_by_klass[local_klass] ||= Set.new
              names_by_klass[local_klass] ||= []
              names_by_klass[local_klass] << name

              data = pl[1..-1].map {|d| d.values }.flatten(1)

              if data.all? {|d| d.is_a?(Set) || d.is_a?(Array)}
                data.each do |sd|
                  scopes_by_klass[local_klass] |= sd
                end
              else
                scopes_by_klass[local_klass] |= data
              end
            end

            result = scopes_by_klass.inject([]) do |memo, (local_klass, scopes)|

              memo += as_jsonapi_data(local_klass,
                local_klass.intersect(:id => scopes), scopes,
                :relationship_scopes => names_by_klass[local_klass],
                :payload => payload, :fields => fields)
              memo
            end

            result
          end

          def extract_fields(fields, klass)
            return if fields.nil?
            raise "Field limits must be passed as a Hash" unless fields.is_a?(Hash)
            resource_name = klass.short_model_name.singular
            return unless fields.has_key?(resource_name)
            fields[resource_name].split(',').map(&:to_sym)
          end

          def jsonapi_linkages(klass, resource_ids, opts = {})
            payload = opts[:payload]

            relationship_scopes = opts[:relationship_scopes]

            jsonapi_assocs = klass.jsonapi_associations.reject do |jl_name, jl_data|
              jl_data.link.is_a?(FalseClass) && jl_data.includable.is_a?(FalseClass)
            end

            resources_name = klass.short_model_name.plural

            resource_ids.each_with_object({}) do |r_id, memo|

              memo[r_id] = jsonapi_assocs.keys.each_with_object({}) do |jl_name, a_memo|
                linked = {}

                if opts[:primary]
                  linked[:links] = {
                    :self    => "#{request.base_url}/#{resources_name}/#{r_id}/relationships/#{jl_name}",
                    :related => "#{request.base_url}/#{resources_name}/#{r_id}/#{jl_name}"
                  }
                end

                payload_scopes = if relationship_scopes.nil? || relationship_scopes.empty?
                  opts[:primary] ? [jl_name.to_s] : []
                else
                  relationship_scopes.map {|rls| "#{rls}.#{jl_name}" }
                end

                payload_scopes.each do |pls|

                  if payload.has_key?(pls) && payload[pls].last.has_key?(r_id)

                    klass = payload[pls].first
                    d = payload[pls].last[r_id]
                    linked[:data] = case d
                    when Set, Array
                      d.map {|da| {:type => klass.short_model_name.singular, :id => da} }
                    when String
                      {:type => klass.short_model_name.singular, :id => d}
                    end
                  end
                end

                next if linked.empty?
                a_memo[jl_name] = linked
              end
            end
          end
        end
      end
    end
  end
end