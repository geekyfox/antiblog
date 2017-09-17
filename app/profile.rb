
require 'json'

module Antiblog
  ##
  # Singleton object for keeping application's runtime configuration.
  #
  module Profile
    def self.init(profile_name = nil)
      profile_name ||= ENV['PROFILE']
      location = File.expand_path("~/.antiblog/#{profile_name}.json")
      @data = File.open(location, 'r') { |f| JSON.parse(f.read) }
      @mock = false
    end

    MOCK_DATA = {
      'api_key' => 'foobarbaz',
      'root_url' => 'http://example.com',
      'site_title' => 'Antiblog MOCK',
      'author' => {
        'name' => 'Anonymous',
        'href' => 'http://geekyfox.net'
      }.freeze,
      'has_powered_by' => true,
      'http_port' => 4000,
      'database' => 'sqlite:/'
    }.freeze

    def self.init_mock(params = {})
      @data = {}
      MOCK_DATA.each { |k, v| @data[k] = v }
      @data['has_micro'] = params.fetch(:has_micro, true)
      @mock = true
    end

    def self.to_h
      {
        'site_title' => site_title,
        'author_name' => author_name,
        'author_href' => author_href,
        'has_powered_by' => powered_by_badge?,
        'root_url' => root_url,
        'donate_link' => donate_link
      }
    end

    def self.api_key
      @data['api_key']
    end

    def self.author_href
      @data.fetch('author', {})['href']
    end

    def self.author_name
      @data.fetch('author', {})['name']
    end

    def self.database
      @data['database']
    end

    def self.powered_by_badge?
      @data.fetch('has_powered_by', true)
    end

    def self.http_port
      @data['http_port']
    end

    def self.micro_tag?
      @data.fetch('has_micro', true)
    end

    def self.mock?
      @mock
    end

    def self.root_url
      @data['root_url']
    end

    def self.site_title
      @data.fetch('site_title', 'The Antiblog')
    end
    
    def self.theme
      @data.fetch('theme', 'classic')
    end
    
    def self.donate_link
      @data['donate_link']
    end
  end
end
