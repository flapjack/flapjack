#!/usr/bin/env ruby

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Helpers
        module ResourceLinks

          def resource_post_links(klass, resources_name, id, assoc_name)
            _, multiple_links = klass.association_klasses
            multiple_klass = multiple_links[assoc_name.to_sym]

            assoc_ids, _ = wrapped_link_params(:multiple => multiple_klass)

            halt(err(403, 'No link ids')) if assoc_ids.empty?

            resource = klass.find_by_id!(id)

            # Not checking for duplication on adding existing to a multiple
            # association, the JSONAPI spec doesn't ask for it
            if multiple_klass.nil?
              # TODO ensure wrapped_link_params will make this unreachable, remove
            else
              assoc_classes = [multiple_klass[:data]] + multiple_klass[:related]
              klass.lock(*assoc_classes) do
                associated = multiple_klass[:data].find_by_ids!(*assoc_ids)
                resource.send(assoc_name.to_sym).add(*associated)
              end
            end
          end

          def resource_get_links(klass, resources_name, id, assoc_name)
            singular_links, multiple_links = klass.association_klasses

            accessor, assoc_type = if multiple_links.has_key?(assoc_name.to_sym)
              [:ids, multiple_links[assoc_name.to_sym][:type]]
            elsif singular_links.has_key?(assoc_name.to_sym)
              [:id, singular_links[assoc_name.to_sym][:type]]
            else
              halt(err(404, 'Unknown association'))
            end

            associated = klass.find_by_id!(id).send(assoc_name).send(accessor)

            links = {
              :self    => "#{request.base_url}/#{resources_name}/#{id}/links/#{assoc_name}",
              :related => "#{request.base_url}/#{resources_name}/#{id}/#{assoc_name}"
            }

            data = case associated
            when Array
              associated.map {|assoc_id| {:type => assoc_type, :id => assoc_id} }
            when String
              {:type => assoc_type, :id => associated}
            else
              nil
            end

            Flapjack.dump_json(:links => links, :data => data)
          end

          def resource_patch_links(klass, resources_name, id, assoc_name)
            singular_links, multiple_links = klass.association_klasses
            singular_klass = singular_links[assoc_name.to_sym]
            multiple_klass = multiple_links[assoc_name.to_sym]

            assoc_ids, _ = wrapped_link_params(:singular => singular_klass,
              :multiple => multiple_klass, :error_on_nil => false)

            resource = klass.find_by_id!(id)

            if !multiple_klass.nil?
              assoc_classes = [multiple_klass[:data]] + multiple_klass[:related]
              klass.lock(*assoc_classes) do
                current_assoc_ids = resource.send(assoc_name.to_sym).ids
                to_remove = current_assoc_ids - assoc_ids
                to_add    = assoc_ids - current_assoc_ids
                tr = to_remove.empty? ? [] : multiple_klass[:data].find_by_ids!(*to_remove)
                ta = to_add.empty?    ? [] : multiple_klass[:data].find_by_ids!(*to_add)
                resource.send(assoc_name.to_sym).delete(*tr) unless tr.empty?
                resource.send(assoc_name.to_sym).add(*ta) unless ta.empty?
              end
            elsif !singular_klass.nil?
              if assoc_ids.nil?
                assoc_classes = [singular_klass[:data]] + singular_klass[:related]
                klass.lock(*assoc_classes) do
                  resource.send("#{assoc_name}=".to_sym, nil)
                end
              else
                halt(err(409, "Trying to add multiple records to singular association '#{assoc_name}'")) if assoc_ids.size > 1
                assoc_classes = [singular_klass[:data]] + singular_klass[:related]
                klass.lock(*assoc_classes) do
                  value = assoc_ids.first.nil? ? nil : singular_klass[:data].find_by_id!(assoc_ids.first)
                  resource.send("#{assoc_name}=".to_sym, value)
                end
              end
            else
              # TODO ensure wrapped_link_params will make this unreachable, remove
            end
          end

          # multiple association
          def resource_delete_links(klass, resources_name, id, assoc_name)
            _, multiple_links = klass.association_klasses
            multiple_klass = multiple_links[assoc_name.to_sym]

            assoc_ids, _ = wrapped_link_params(:multiple => multiple_klass)

            halt(err(403, 'No link ids')) if assoc_ids.empty?

            resource = klass.find_by_id!(id)

            assoc = resource.send(assoc_name.to_sym)
            associated = assoc.find_by_ids!(*assoc_ids)
            assoc.delete(*associated)
          end

        end
      end
    end
  end
end