
require 'set'

module Antiblog
  ##
  # Domain objects.
  #
  module Domain
    ##
    # Set of tags.
    #
    class Tags < Set
      def to_liquid
        empty? ? nil : to_a.sort!
      end
    end

    ##
    # Single antilog entry.
    #
    class Entry < Hash
      def id
        self['id']
      end

      def id=(x)
        self['id'] = x
        self['color'] = (x % 6) + 1
      end

      def content
        self['content']
      end

      def content=(x)
        self['content'] = x
      end

      def permalink
        self['permalink']
      end

      def permalink=(x)
        self['permalink'] = x
      end

      def pub_date=(x)
        self['pub_date'] = x.is_a?(Time) ? x.getgm.rfc822 : x.to_s
      end

      def read_more=(x)
        self['read_more'] = x
      end

      def redirect_url
        self['redirect_url']
      end

      def redirect_url=(x)
        self['redirect_url'] = x
      end

      def series
        self['series'] = [] unless key?('series')
        self['series']
      end

      def summary=(x)
        self['summary'] = x
      end

      def tags
        self['tags'] = Tags.new unless key?('tags')
        self['tags']
      end

      def title=(x)
        raise if x.nil?
        self['title'] = x == '' ? "##{id}" : x
      end

      def teaser
        self['teaser']
      end

      def teaser=(x)
        self['teaser'] = x
      end
    end

    ##
    # Base rendering context.
    #
    class Context
      attr_reader :entries

      def initialize
        @normal_or_meta = :normal
        @entries = []
      end

      def normal?
        @normal_or_meta == :normal
      end

      def meta?
        @normal_or_meta == :meta
      end

      def meta!
        @normal_or_meta = :meta
      end

      def to_h
        Profile.to_h.merge(
          'entries' => @entries
        )
      end

      def lookup
        result = {}
        entries.each { |x| result[x.id] = x }
        result
      end

      def empty?
        @entries.empty?
      end

      def <<(row)
        @entries << Entry.new.tap { |e| translate(e, row) }
      end

      def translate(_, _)
        raise 'Not implemented'
      end
    end

    ##
    # Base context for rendering webpages.
    #
    class WebContext < Context
      attr_reader :entries

      def initialize
        super
        @tag_cloud = []
      end

      def translate(e, row)
        e.id = row[:id]
        e.title = row[:title]
        e.redirect_url = row[:redirect_url]
        e.read_more = false
        translate_content(e, row[:body], row[:teaser])
      end

      def translate_content(entry, body, teaser)
        if body == teaser
          entry.tags << 'micro' if Profile.micro_tag?
          entry.content = teaser
        elsif page?
          entry.content = teaser.strip.sub(%r{<br \/>\z}, '')
          entry.read_more = true
        else
          entry.content = body
        end
        entry.teaser = teaser
      end

      def add_tag(tag, count)
        @tag_cloud << {
          'name' => tag,
          'count' => count,
          'color' => count % 6 + 1
        }
      end

      def tag_cloud
        return nil if @tag_cloud.empty?
        @tag_cloud.sort do |first, second|
          r = second['count'] <=> first['count']
          r = first['name'] <=> second['name'] if r.zero?
          r
        end
      end

      def page_title
        Profile.site_title
      end

      def page_url
        Profile.root_url
      end

      def page_description
        if Profile.author_name
          "#{Profile.site_title} by #{Profile.author_name}"
        else
          Profile.site_title
        end
      end

      def to_h
        super.merge(
          'not_found' => empty?,
          'page_title' => page_title,
          'page_url' => page_url,
          'page_description' => page_description,
          'tag_cloud' => tag_cloud
        )
      end
    end

    ##
    # Context of rendering an RSS feed.
    #
    class RssContext < Context
      def translate(e, row)
        e.id = row[:entry_id]
        e.title = row[:title]
        e.summary = row[:teaser]
        e.pub_date = row[:date_posted]
      end
    end

    ##
    # Context of rendering a page with a single entry.
    #
    class EntryContext < WebContext
      attr_writer :redirect_url

      def page?
        false
      end

      def page_title
        return super if @entries.empty?
        "#{Profile.site_title} : #{@entries[0]['title']}"
      end

      def page_url
        return super if @entries.empty?
        Profile.root_url + @entries[0].permalink
      end

      def page_description
        return super if @entries.empty?
        @entries[0].teaser
      end

      def redirect_url
        return @redirect_url if @redirect_url
        return nil if @entries.empty?
        @entries[0].redirect_url
      end
    end

    ##
    # Reference to a multi-entry page.
    #
    class PageRef
      attr_reader :tag, :index

      def initialize(tag, index)
        @tag = tag
        @index = index
      end

      def self.make(a = nil, b = nil)
        if a.nil?
          new(nil, 1)
        elsif b.nil?
          ix = PageRef.parse_index(a)
          ix.nil? ? new(a, 1) : new(nil, ix)
        else
          ix = PageRef.parse_index(b)
          raise "Bad number: #{b}" unless ix
          new(a, ix)
        end
      end

      def last?
        @index == :last
      end

      def abs_index(page_count)
        return page_count if last?
        @index
      end

      def prev(page_count)
        x = abs_index(page_count)
        return nil if x <= 1
        PageRef.new(@tag, x - 1).url
      end

      def next(page_count)
        x = abs_index(page_count)
        return nil if x >= page_count
        PageRef.new(@tag, x + 1).url
      end

      def url
        ret = '/page'
        ret << "/#{@tag}" if @tag
        ret << "/#{@index}" if @index > 1
        ret = '/' if ret == '/page'
        ret
      end

      def self.parse_index(x)
        return x.to_i if x =~ /^[0-9]+$/
        return :last if x == 'last'
        nil
      end
    end

    ##
    # Context for rendering multi-entry page.
    #
    class PageContext < WebContext
      attr_accessor :prev
      attr_accessor :next

      def page?
        true
      end

      def to_h
        super.merge(
          'prev' => @prev,
          'next' => @next,
          'navi' => @prev || @next
        )
      end
    end
  end
end
