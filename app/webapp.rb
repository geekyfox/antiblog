require 'liquid'
require 'sequel'
require 'sinatra/base'

require_relative 'database'

module Antiblog
  module WebApp
    ##
    # Main application class.
    #
    class WebApp < Sinatra::Base
      def initialize(profile_name)
        super()
        Profile.init(profile_name)
        Database.init
      end

      def secure
        if params['api_key'].nil?
          status 403
          body 'api_key is missing'
        elsif params['api_key'] != Profile.api_key
          status 403
          body 'api_key is invalid'
        else
          yield
        end
      end

      get '/' do
        locals = Database.page_locals
        liquid(:list, locals: locals.to_h)
      end

      get '/page/:ref' do
        locals = Database.page_locals(params['ref'])
        liquid(:list, locals: locals.to_h)
      end

      get '/page/:ref/:secref' do
        locals = Database.page_locals(params['ref'], params['secref'])
        liquid(:list, locals: locals.to_h)
      end

      get '/entry/:ref' do
        locals = Database.entry_locals(params['ref'])
        if locals.redirect_url.nil?
          liquid(:list, locals: locals.to_h)
        else
          redirect(locals.redirect_url)
        end
      end

      get '/meta/:ref' do
        locals = Database.meta_locals(params['ref'])
        if locals.redirect_url.nil?
          liquid(:list, locals: locals.to_h)
        else
          redirect(locals.redirect_url)
        end
      end

      get '/rss.xml' do
        content_type :xml
        locals = Database.rss_feed_locals
        liquid(:rss, locals: locals.to_h)
      end

      get '/api/index' do
        secure do
          content_type :json
          Database.api_index.to_json
        end
      end

      post '/api/create' do
        secure do
          e = JSON.parse(params['payload'])
          id = Database.create_entry e
          content_type :json
          { content: id }.to_json
        end
      end

      post '/api/update' do
        secure do
          e = JSON.parse(params['payload'])
          Database.update_entry e
          content_type :json
          { result: 'OK' }.to_json
        end
      end
    end
  end
end
