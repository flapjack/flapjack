
guard 'rspec', :cli => '--format Fuubar --format html --out tmp/spec.html --require ./spec/support/uncolored_doc_formatter.rb --format UncoloredDocFormatter --out tmp/spec_doc.txt --require ./spec/support/profile_all_formatter.rb --format ProfileAllFormatter --out tmp/spec_profile.txt', :version => 2 do
  watch(%r{^spec/.+_spec\.rb$})
  watch(%r{^lib/(.+)\.rb$})     { |m| "spec/lib/#{m[1]}_spec.rb" }
  watch('spec/spec_helper.rb')  { "spec" }
end

# NB: seems to be buggy with the default --progress formatter, was
# causing failures to parse the features
guard 'cucumber', :cli => '--no-profile --color --format fuubar --strict' do
  watch(%r{^features/.+\.feature$})
  watch(%r{^features/support/.+$})          { 'features' }
  watch(%r{^features/step_definitions/(.+)_steps\.rb$}) { |m| Dir[File.join("**/#{m[1]}.feature")][0] || 'features' }
end
