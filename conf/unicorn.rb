
require_relative '../app/profile'
Antiblog::Profile.init

worker_processes 4
preload_app true

listen Antiblog::Profile.http_port
