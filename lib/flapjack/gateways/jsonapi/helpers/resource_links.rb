#!/usr/bin/env ruby

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Helpers
        module ResourceLinks

          # NB: these all take a single primary id, but the code is general
          # enough to handle an array of ids, in case we want to extend
          # on current behaviour.

          def resource_post_links(klass, id, assoc_name, options)
            assoc_ids, _ = wrapped_params(assoc_name)
            halt(err(403, "No link ids")) if assoc_ids.empty?

            associated = assoc_klass.find_by_ids!(*tag_ids)

            singular_links   = options[:singular_links]   || {}
            collection_links = options[:collection_links] || {}

            klass.find_by_ids!(id).each do |r|
              # Not checking for duplication on adding existing to a multiple
              # association, the JSONAPI spec doesn't ask for it
              if singular_links.has_key?(assoc_name)
                halt(err(409, "Association '#{assoc_name}' is already populated")) unless r.send(assoc_name.to_sym).nil?
              end
            end.each do |r|
              if collection_links.has_key?(assoc_name)
                r.send(assoc_name.to_sym).add(*associated)
              elsif singular_links.has_key?(assoc_name)
                r.send("#{assoc_name}=".to_sym)
              end
            end
          end

          def resource_get_links(klass, id, assoc_name, options)
            singular_links   = options[:singular_links]   || {}
            collection_links = options[:collection_links] || {}

            assoc_accessor = if collection_links.has_key?(assoc_name)
              :ids
            elsif singular_links.has_key?(assoc_name)
              :id
            end

            associated = klass.find_by_ids!(id).each_with_object({}) do |r, memo|
              memo[r.id] = r.send(assoc_name).send(assoc_accessor)
            end

            {assoc_name => associated[id]}
          end

          def resource_put_links(klass, id, assoc_name, options)
            assoc_ids, _ = wrapped_params(assoc_name)

            resources  = klass.find_by_ids!(id)

            singular_links   = options[:singular_links]   || {}
            collection_links = options[:collection_links] || {}

            associated_to_change = resources.each_with_object do |memo, r|
              if collection_links.has_key?(assoc_name)
                assoc_klass = collection_links[assoc_name]
                current_assoc_ids = r.send(assoc_name.to_sym).ids
                memo[r.id] = [
                  assoc_klass.find_by_ids!(current_assoc_ids - links[assoc_name]), # to_remove
                  assoc_klass.find_by_ids!(links[assoc_name] - current_assoc_ids)  # to_add
                ]
              elsif singular_links.has_key?(assoc_name)
                memo[r.id] = links[assoc_name].nil? ? nil : assoc_klass.find_by_id!(links[assoc_name])
              end
            end

            resources.each do |r|
              value = associated_to_change[r.id]
              if collection_links.has_key?(assoc_name)
                to_remove = value.first
                to_add    = value.last
                r.send(assoc.to_sym).delete(*to_remove) unless to_remove.empty?
                r.send(assoc.to_sym).add(*to_add) unless to_add.empty?
              elsif singular_links.has_key?(assoc_name)
                r.send("#{assoc}=".to_sym, value)
              end
            end
          end

          # singular association
          def resource_delete_link(klass, id, assoc_name, assoc_klass)
            klass.find_by_ids!(id).each do |r|
              # validate that the associated record exists
              halt(err(403, "No association '#{assoc_name}' to delete for id '#{r.id}'")) if r.send(assoc_name.to_sym).nil?
            end.each do |r|
              r.send("#{assoc_name}=".to_sym, nil)
            end
          end

          # multiple association
          def resource_delete_links(klass, id, assoc_name, assoc_klass, assoc_ids)
            halt(err(403, "No link ids")) if assoc_ids.empty?

            # validate that the association ids actually exist in the associations
            klass.find_by_ids!(id).each_with_object({}) do |r, memo|
              memo[r] = r.send(assoc_name.to_sym).find_by_ids!(assoc_ids)
            end.each_pair do |r, associated|
              r.send(assoc_name.to_sym).delete(*associated)
            end
          end

        end
      end
    end
  end
end