require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:test) do |t|
  t.pattern = "spec/ledger_spec.rb"
end

# Deliberately failing spec against our own design. Expected to fail.
RSpec::Core::RakeTask.new(:failing) do |t|
  t.pattern = "spec/failing/design_spec.rb"
end

task default: :test
