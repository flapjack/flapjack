#!/usr/bin/env ruby

require 'active_support/inflector'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Helpers
        module Resources

          ISO8601_PAT = "(?:[1-9][0-9]*)?[0-9]{4}-" \
                        "(?:1[0-2]|0[1-9])-" \
                        "(?:3[0-1]|0[1-9]|[1-2][0-9])T" \
                        "(?:2[0-3]|[0-1][0-9]):" \
                        "[0-5][0-9]:[0-5][0-9](?:\\.[0-9]+)?" \
                        "(?:Z|[+-](?:2[0-3]|[0-1][0-9]):[0-5][0-9])?"

          # TODO refactor some of these methods into a module, included in data/ classes

          def normalise_json_data(attribute_types, data)
            record_data = data.dup
            attribute_types.each_pair do |name, type|
              t = record_data[name.to_s]
              next unless t.is_a?(String) && :timestamp.eql?(type)
              begin
                record_data[name.to_s] = DateTime.parse(t)
              rescue ArgumentError
                record_data[name.to_s] = nil
              end
            end
            symbolize(record_data)
          end

          def parse_range_or_value(name, pattern, v, opts = {}, &block)
            rangeable = opts[:rangeable]

            if rangeable && (v =~ /\A(?:(#{pattern})\.\.(#{pattern})|(#{pattern})\.\.|\.\.(#{pattern}))\z/)
              start = nil
              start_s = Regexp.last_match(1) || Regexp.last_match(3)
              unless start_s.nil?
                start = yield(start_s)
                halt(err(403, "Couldn't parse #{name} '#{start_s}'")) if start.nil?
              end

              finish = nil
              finish_s = Regexp.last_match(2) || Regexp.last_match(4)
              unless finish_s.nil?
                finish = yield(finish_s)
                halt(err(403, "Couldn't parse #{name} '#{finish_s}'")) if finish.nil?
              end

              if !start.nil? && !finish.nil? && (start > finish)
                halt(err(403, "Range order cannot be inversed"))
              else
                Zermelo::Filters::IndexRange.new(start, finish, :by_score => true)
              end

            elsif v =~ /\A#{pattern}\z/
              t = yield(v)
              halt(err(403, "Couldn't parse #{name} '#{v}'")) if t.nil?
              t
            else
              halt(err(403, "Invalid #{name} parameter '#{v}'"))
            end
          end

          def filter_params(klass, filter)
            attributes = if klass.respond_to?(:jsonapi_methods)
              (klass.jsonapi_methods[:get] || {}).attributes || []
            else
              []
            end

            attribute_types = klass.attribute_types

            rangeable_attrs = []
            attrs_by_type = {}

            klass.send(:with_index_data) do |idx_data|
              idx_data.each do |k, d|
                next unless d.index_klass == ::Zermelo::Associations::RangeIndex
                rangeable_attrs << k
              end
            end

            Zermelo::ATTRIBUTE_TYPES.keys.each do |at|
              attrs_by_type[at] = attributes.select do |a|
                at.eql?(attribute_types[a])
              end
            end

            filter.each_with_object({}) do |filter_str, memo|
              k, v = filter_str.split(':', 2)
              halt(err(403, "Single filter parameters must be 'key:value'")) if k.nil? || v.nil?

              value = if attrs_by_type[:string].include?(k.to_sym) || :id.eql?(k.to_sym)
                if v =~ %r{^/(.+)/$}
                  Regexp.new(Regexp.last_match(1))
                elsif v =~ /\|/
                  v.split('|')
                else
                  v
                end
              elsif attrs_by_type[:boolean].include?(k.to_sym)
                case v.downcase
                when '0', 'f', 'false', 'n', 'no'
                  false
                when '1', 't', 'true', 'y', 'yes'
                  true
                end

              elsif attrs_by_type[:timestamp].include?(k.to_sym)
                parse_range_or_value('timestamp', ISO8601_PAT, v, :rangeable => rangeable_attrs.include?(k.to_sym)) {|s|
                  begin; DateTime.parse(s); rescue ArgumentError; nil; end
                }
              elsif attrs_by_type[:integer].include?(k.to_sym)
                parse_range_or_value('integer', '\d+', v, :rangeable => rangeable_attrs.include?(k.to_sym)) {|s|
                  s.to_i
                }
              elsif attrs_by_type[:float].include?(k.to_sym)
                parse_range_or_value('float', '\d+(\.\d+)?', v, :rangeable => rangeable_attrs.include?(k.to_sym)) {|s|
                  s.to_f
                }
              end

              halt(err(403, "Invalid filter key '#{k}'")) if value.nil?
              memo[k.to_sym] = value
            end
          end

          def resource_filter_sort(klass, options = {})
            options[:sort] ||= 'id'
            scope = klass

            unless params[:filter].nil?
              unless params[:filter].is_a?(Array)
                halt(err(403, "Filter parameters must be passed as an Array"))
              end
              filter_ops = filter_params(klass, params[:filter])
              scope = scope.intersect(filter_ops)
            end

            sort_opts = if params[:sort].nil?
              options[:sort].to_sym
            else
              sort_params = params[:sort].split(',')

              if sort_params.any? {|sp| sp !~ /^(?:\+|-)/ }
                halt(err(403, "Sort parameters must start with +/-"))
              end

              sort_params.each_with_object({}) do |sort_param, memo|
                sort_param =~ /^(\+|\-)([a-z_]+)$/i
                rev  = Regexp.last_match(1)
                term = Regexp.last_match(2)
                memo[term.to_sym] = (rev == '-') ? :desc : :asc
              end
            end

            scope = scope.sort(sort_opts)
            scope
          end

          def paginate_get(dataset, options = {})
            return([[], {}, {}]) if dataset.nil?

            total = dataset.count
            return([[], {}, {}]) if total == 0

            page = options[:page].to_i
            page = (page > 0) ? page : 1

            per_page = options[:per_page].to_i
            per_page = (per_page > 0) ? per_page : 20

            total_pages = (total.to_f / per_page).ceil

            pages = set_page_numbers(page, total_pages)
            links = create_links(pages)
            headers['Link']        = create_link_header(links) unless links.empty?
            headers['Total-Count'] = total_pages.to_s

            [dataset.page(page, :per_page => per_page),
              links,
              {
                :pagination => {
                  :page        => page,
                  :per_page    => per_page,
                  :total_pages => total_pages,
                  :total_count => total
                }
              }
            ]
          end

          def set_page_numbers(page, total_pages)
            pages = {}
            pages[:first] = 1 # if (total_pages > 1) && (page > 1)
            pages[:prev]  = page - 1 if (page > 1)
            pages[:next]  = page + 1 if page < total_pages
            pages[:last]  = total_pages # if (total_pages > 1) && (page < total_pages)
            pages
          end

          def create_links(pages)
            url_without_params = request.url.split('?').first
            per_page = params[:per_page] # ? params[:per_page].to_i : 20

            links = {}
            pages.each do |key, value|
              page_params = {'page' => value }
              page_params.update('per_page' => per_page) unless per_page.nil?
              new_params = request.params.merge(page_params)
              links[key] = "#{url_without_params}?#{new_params.to_query}"
            end
            links
          end

          def create_link_header(links)
            links.collect {|(k, v)| "<#{v}; rel=\"#{k}\"" }.join(', ')
          end

        end
      end
    end
  end
end