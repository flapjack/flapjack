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
            assoc_ids, _ = wrapped_link_params(assoc_name)
            halt(err(403, "No link ids")) if assoc_ids.empty?

            singular_klass   = (options[:singular_links]   || {})[assoc_name]
            collection_klass = (options[:collection_links] || {})[assoc_name]

            associated = (singular_klass || collection_klass).find_by_ids!(*assoc_ids)

            klass.find_by_ids!(id).each do |r|
              # Not checking for duplication on adding existing to a multiple
              # association, the JSONAPI spec doesn't ask for it
              unless singular_klass.nil?
                halt(err(409, "Association '#{assoc_name}' is already populated")) unless r.send(assoc_name.to_sym).nil?
                halt(err(409, "Trying to add multiple records to singular association '#{assoc_name}'")) if associated.size > 1
              end
            end.each do |r|
              if !collection_klass.nil?
                r.send(assoc_name.to_sym).add(*associated)
              elsif !singular_klass.nil?
                r.send("#{assoc_name}=".to_sym, associated.first)
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

            Flapjack.dump_json(assoc_name => associated[id])
          end

          def resource_put_links(klass, id, assoc_name, options)
            assoc_ids, _ = wrapped_link_params(assoc_name)

            resources  = klass.find_by_ids!(id)

            singular_klass   = (options[:singular_links]   || {})[assoc_name]
            collection_klass = (options[:collection_links] || {})[assoc_name]

            associated_to_change = resources.each_with_object({}) do |r, memo|
              if !collection_klass.nil?
                current_assoc_ids = r.send(assoc_name.to_sym).ids
                to_remove = current_assoc_ids - assoc_ids
                to_add    = assoc_ids - current_assoc_ids
                memo[r.id] = [
                  to_remove.empty? ? [] : collection_klass.find_by_ids!(*to_remove),
                  to_add.empty?    ? [] : collection_klass.find_by_ids!(*to_add)
                ]
              elsif !singular_klass.nil?
                halt(err(409, "Trying to add multiple records to singular association '#{assoc_name}'")) if assoc_ids.size > 1
                memo[r.id] = assoc_ids.first.nil? ? nil : singular_klass.find_by_id!(assoc_ids.first)
              end
            end

            resources.each do |r|
              value = associated_to_change[r.id]
              if !collection_klass.nil?
                to_remove = value.first
                to_add    = value.last
                r.send(assoc_name.to_sym).delete(*to_remove) unless to_remove.empty?
                r.send(assoc_name.to_sym).add(*to_add) unless to_add.empty?
              elsif !singular_klass.nil?
                r.send("#{assoc_name}=".to_sym, value)
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
              assoc = r.send(assoc_name.to_sym)
              memo[assoc] = assoc.find_by_ids!(*assoc_ids)
            end.each_pair do |assoc, associated|
              assoc.delete(*associated)
            end
          end

        end
      end
    end
  end
end