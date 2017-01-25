require_relative '../app/webapp'

run Antiblog::WebApp::WebApp.new(ENV['PROFILE'])
