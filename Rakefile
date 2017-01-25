require 'rdoc/task'
require 'rake/testtask'

task default: %w(test)

Rake::TestTask.new(:test) do |t|
  t.test_files = ['test/test_suite.rb']
  t.warning = false
end

RDoc::Task.new(:doc) do |doc|
  doc.main = 'README.rdoc'
  doc.title = 'Antisync Documentation'
  doc.rdoc_dir = 'doc'
  doc.rdoc_files = FileList.new %w(lib/**/*.rb *.rdoc)
end

task :rotate, [:env_name] do |_, args|
  require_relative 'app/profile'
  require_relative 'app/database'
  Antiblog::Profile.init(args['env_name'])
  Antiblog::Database.init
  Antiblog::Database.rotate
end
