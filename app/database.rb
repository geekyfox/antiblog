
require 'sequel'
require 'tdp'
require_relative 'domain'
require_relative 'profile'

module Antiblog
  ##
  # Data access logic.
  #
  module Database
    @db = nil

    def self.init
      @db = Sequel.connect(Profile.database)
      TDP.execute(@db) do |engine|
        engine << File.expand_path("#{__dir__}/../schema")
        engine.bootstrap
        engine.upgrade
      end
    end

    def self.[](x)
      @db[x]
    end

    def self.entry_locals(ref, context = nil)
      context ||= Domain::EntryContext.new
      @db.transaction do
        Base.retrieve_entry(ref, context)
      end
      context
    end

    def self.meta_locals(ref)
      context = Domain::EntryContext.new.tap(&:meta!)
      entry_locals(ref, context)
    end

    def self.page_locals(a = nil, b = nil)
      ref = Domain::PageRef.make(a, b)
      context = Domain::PageContext.new
      context.meta! if ref.tag == 'meta'
      @db.transaction do
        Base.retrieve_page(ref, context)
      end
      context
    end

    def self.create_entry(payload)
      @db.transaction { Mutate.create(payload) }
    end

    def self.update_entry(payload)
      @db.transaction { Mutate.update(payload) }
    end

    def self.rss_feed_locals
      @db.transaction do
        Rss.get.tap do |context|
          Symlinks.inject(context, context.entries)
        end
      end
    end

    def self.api_index
      @db.transaction do
        @db[:entry].select(:id, :md5_signature).map do |r|
          { id: r[:id], signature: r[:md5_signature] }
        end
      end
    end

    def self.id_by_ref(ref, context)
      id = Symlinks.find(context, ref)
      return id unless id.nil?
      return ref.to_i if ref =~ /^[0-9]+$/
    end

    def self.rotate
      @db.transaction do
        q = @db[:entry].select(1).where(invisible: false)
        if q.empty?
          log('No visible entries')
          return
        end

        while rotate_once
        end
      end
    end

    def self.rotate_once
      Mutate.slide_ranks(1)
      row = last_entry
      @db[:entry].where(id: row[:id]).update(rank: 1)
      if row[:invisible]
        log("Promoted invisible entry #{row[:id]}")
      else
        log("Promoted entry #{row[:id]}")
        Rss.rotate(row[:id])
      end
      row[:invisible]
    end

    def self.last_entry
      @db[:entry]
        .select(:id, :invisible)
        .order(Sequel.desc(:rank))
        .first
    end

    def self.log(msg)
      puts msg unless Profile.mock?
    end

    ##
    # Base data access logic.
    #
    module Base
      def self.retrieve_page(ref, context)
        real_index = ref.last? ? Database.page_count(ref.tag) : ref.index
        fetch_entries(context) do |q|
          q = Tags.apply_filter(q, ref.tag)
          q.order_by(:rank).limit(5).offset(real_index * 5 - 5)
        end
        decorate(context)
        inject_prev_next(ref, context)
        context
      end

      def self.inject_prev_next(ref, context)
        count = page_count(ref.tag)
        context.prev = ref.prev(count)
        context.next = ref.next(count)
      end

      def self.retrieve_entry(ref, context)
        if ref == 'random'
          retrieve_random_entry(context)
        else
          id = Database.id_by_ref(ref, context)
          fetch_entries(context) { |q| q.where(id: id) } unless id.nil?
        end
        decorate(context) if context.redirect_url.nil?
      end

      def self.fetch_entries(context)
        q = Database[:entry]
        q = q.select(:id, :title, :teaser, :body, :redirect_url)
        q = yield q
        q.each { |row| context << row }
        context
      end

      def self.retrieve_random_entry(context)
        id = random_entry_id
        return if id.nil?
        e = Domain::Entry.new
        e.id = id
        Symlinks.inject(context, [e])
        context.redirect_url = Profile.root_url + e.permalink
      end

      def self.random_entry_id
        ct = entry_count
        return nil if ct.zero?
        Database[:entry]
          .select(:id)
          .where(invisible: false)
          .order_by(:rank).limit(1).offset(rand(ct))
          .map { |r| r[:id] }
          .first
      end

      def self.decorate(context)
        Symlinks.inject(context, context.entries)
        Tags.inject_tags(context)
        Tags.inject_cloud(context)
        Series.inject(context) unless context.page?
      end

      def self.page_count(tag = nil)
        x = entry_count(tag)
        (x + 4) / 5
      end

      def self.entry_count(tag = nil)
        q = Database[:entry].select(1)
        q = Tags.apply_filter(q, tag)
        q.count
      end
    end

    ##
    # Functions for creating and updating entries.
    #
    module Mutate
      EMPTY_ENTRY = {
        body: '',
        teaser: '',
        title: '',
        invisible: true
      }.freeze

      def self.create(payload)
        generate_id.tap do |id|
          create_empty(id)
          update_existing(id, payload)
        end
      end

      def self.update(payload)
        ensure_exists(payload['id'])
        update_existing(payload['id'], payload)
      end

      def self.create_empty(id)
        rank = generate_rank
        row = EMPTY_ENTRY.merge(
          id: id,
          rank: rank,
          md5_signature: ''
        )
        Database[:entry].insert(row)
      end

      def self.generate_rank
        max_rank = Database[:entry].max(:rank)
        return 1 if max_rank.nil?
        rank = rand(max_rank) + 1
        slide_ranks(rank)
        rank
      end

      def self.generate_id
        id = nil
        flag = false
        until flag
          id = rand(9_000_000) + 1_000_000
          flag = Database[:entry].where(id: id).count.zero?
        end
        id
      end

      def self.ensure_exists(id)
        return unless Database[:entry].where(id: id).count.zero?
        create_empty(id)
      end

      def self.update_existing(id, entry)
        if entry['url'].nil?
          update_normal(id, entry)
        else
          update_redirect(id, entry)
        end
        Symlinks.update(id, 'normal', entry['symlink'])
        Symlinks.update(id, 'meta', entry['metalink'])
      end

      def self.update_normal(id, entry)
        Database[:entry].where(id: id).update(
          title: entry['title'] || '',
          teaser: entry['summary'] || cut_body(entry['body']),
          body: entry['body'],
          invisible: false,
          md5_signature: entry['signature'],
          redirect_url: nil
        )
        Tags.update(id, entry['tags'])
        Series.update(id, entry['series'])
      end

      def self.cut_body(body)
        return body if body.length <= 600
        summary = body[0, 600]
        ix = summary.rindex "\n"
        return summary[0, ix] if ix
        ix = summary.rindex ' '
        return summary[0, ix] if ix
        summary
      end

      def self.update_redirect(id, entry)
        Database[:entry].where(id: id).update(
          EMPTY_ENTRY.merge(
            md5_signature: entry['signature'],
            redirect_url: entry['url'],
            invisible: true
          )
        )
        Tags.delete(id)
        Series.delete(id)
        Rss.delete(id)
      end

      def self.slide_ranks(rank)
        Database[:entry]
          .select(:id).where('rank >= ?', rank)
          .order(Sequel.desc(:rank))
          .each do |row|
            Database[:entry]
              .where(id: row[:id])
              .update('rank = rank + 1')
          end
      end
    end

    ##
    # Functions for managing RSS feed data.
    #
    module Rss
      def self.get
        Domain::RssContext.new.tap do |context|
          Database[:rss_entry]
            .join(:entry, 'entry.id = rss_entry.entry_id')
            .select(:entry_id, :title, :teaser, :date_posted)
            .order_by(:feed_position)
            .each { |row| context << row }
        end
      end

      def self.delete(entry_id)
        Database[:rss_entry].where(entry_id: entry_id).delete
      end

      def self.rotate(entry_id)
        q = Database[:rss_entry].where(entry_id: entry_id)
        return unless q.empty?
        slide_ranks
        Database[:rss_entry].insert(
          feed_position: 1,
          entry_id: entry_id
        )
      end

      def self.slide_ranks
        Database[:rss_entry]
          .select(:entry_id)
          .order(Sequel.desc(:feed_position))
          .each do |row|
            Database[:rss_entry]
              .where(entry_id: row[:entry_id])
              .update('feed_position = feed_position + 1')
          end
        Database[:rss_entry].where('feed_position > 10').delete
      end
    end

    ##
    # Functions for managing series of posts.
    #
    module Series
      ##
      # Series data retriever.
      #
      class Fetcher
        attr_reader :series_cache
        attr_reader :ref_cache

        def initialize(context)
          @context = context
          @series_cache = Hash.new do |h, key|
            h[key] = Series.retrieve(key)
          end
          @ref_cache = Hash.new do |h, id|
            h[id] = Domain::Entry.new(id)
          end
        end

        def fetch
          lookup = @context.lookup
          Database[:series_assignment]
            .select(:entry_id, :series, :index)
            .where('entry_id in ?', lookup.keys)
            .order_by(:series)
            .each { |r| lookup[r[:entry_id]].series << make(r) }
        end

        def each_field(index, series)
          ss = @series_cache[series]
          yield 'first', ss[0][0]
          yield 'last', ss[-1][0]
          yield 'prev', find_prev(index, ss)
          yield 'next', find_next(index, ss)
        end

        def find_prev(index, ss)
          prev_index = nil
          prev = nil
          ss.each do |r|
            next if r[1] >= index
            if prev_index.nil? || prev_index < r[1]
              prev = r[0]
              prev_index = r[1]
            end
          end
          prev
        end

        def find_next(index, ss)
          next_index = nil
          next_id = nil
          ss.each do |r|
            next if r[1] <= index
            if next_index.nil? || next_index > r[1]
              next_id = r[0]
              next_index = r[1]
            end
          end
          next_id
        end

        def make(row)
          ret = {}
          each_field(row[:index], row[:series]) do |key, id|
            ret[key] = @ref_cache[id] if id
          end
          ret
        end
      end

      def self.retrieve(name)
        Database[:series_assignment]
          .select(:entry_id, :index)
          .where(series: name)
          .order_by(:index)
          .map { |r| [r[:entry_id], r[:index]].freeze }
          .freeze
      end

      def self.delete(id)
        Database[:series_assignment].where(entry_id: id).delete
      end

      def self.update(id, series)
        delete(id)
        return if series.nil?
        series.each do |x|
          Database[:series_assignment].insert(
            entry_id: id,
            index: x['index'],
            series: x['series']
          )
        end
      end

      def self.inject(context)
        return if context.empty?
        fetcher = Fetcher.new(context)
        fetcher.fetch
        Symlinks.inject(context, fetcher.ref_cache.values)
      end
    end

    ##
    # Functions for managing symlinks data.
    #
    module Symlinks
      ##
      # Hash of symlinks.
      #
      class SymlinkHash
        def initialize(context)
          @context = context
          @data = Hash.new { |hash, key| hash[key] = {} }
        end

        def put(entry_id, kind, link)
          @data[entry_id][kind] = link
        end

        def get(entry_id)
          links = @data[entry_id]
          normal = links['normal']
          meta = links['meta']
          return "/meta/#{meta}" if meta && @context.meta?
          return "/entry/#{normal}" if normal
          return "/meta/#{meta}" if meta
          "/entry/#{entry_id}"
        end

        def meta?(entry_id)
          !@data[entry_id]['meta'].nil?
        end
      end

      def self.update(id, kind, link)
        Database[:symlink]
          .where(entry_id: id, kind: kind)
          .delete
        return if link.nil?
        Database[:symlink].insert(
          entry_id: id,
          kind: kind,
          link: link
        )
      end

      def self.inject(context, entries = nil)
        entries ||= context.entries
        tmp = SymlinkHash.new(context)
        each(entries.map(&:id)) do |entry_id, kind, link|
          tmp.put(entry_id, kind, link)
        end
        entries.each do |entry|
          entry.permalink = tmp.get(entry.id)
          entry.tags << 'meta' if tmp.meta?(entry.id)
        end
      end

      def self.each(entry_ids)
        Database[:symlink]
          .select(:entry_id, :kind, :link)
          .where('entry_id in ?', entry_ids)
          .each { |r| yield r[:entry_id], r[:kind], r[:link] }
      end

      def self.find(context, ref)
        kind = context.meta? ? 'meta' : 'normal'
        Database[:symlink]
          .select(:entry_id)
          .where(link: ref, kind: kind)
          .map { |r| r[:entry_id] }
          .first
      end
    end

    ##
    # Functions for managing tags data.
    #
    module Tags
      def self.update(entry_id, tags)
        delete(entry_id)
        return if tags.nil?
        tags.each do |x|
          Database[:entry_tag].insert(entry_id: entry_id, tag: x)
        end
      end

      def self.delete(entry_id)
        Database[:entry_tag].where(entry_id: entry_id).delete
      end

      def self.inject_tags(context)
        return if context.empty?
        lookup = context.lookup
        Database[:entry_tag]
          .select(:tag, :entry_id)
          .where('entry_id in ?', lookup.keys)
          .each { |r| lookup[r[:entry_id]].tags << r[:tag] }
      end

      def self.inject_cloud(context)
        each do |tag, count|
          context.add_tag(tag, count)
        end
      end

      def self.each
        Database[:entry_tag].group_and_count(:tag).each do |row|
          yield row[:tag], row[:count]
        end
        if Profile.micro_tag?
          count = Database[:entry].where('body = teaser').count
          yield 'micro', count unless count.zero?
        end
        count = Database[:symlink].where(kind: 'meta').count
        yield 'meta', count unless count.zero?
      end

      def self.apply_filter(q, tag)
        q = q.where(invisible: false)
        return q if tag.nil?
        return q.where('body = teaser') if tag == 'micro'
        return q.where(meta_tag_cte) if tag == 'meta'
        q.where(tag_cte(tag))
      end

      def self.tag_cte(tag)
        Database[:entry_tag]
          .select(1)
          .where(tag: tag)
          .where('entry_id = entry.id')
          .exists
      end

      def self.meta_tag_cte
        Database[:symlink]
          .select(1)
          .where(kind: 'meta')
          .where('entry_id = entry.id')
          .exists
      end
    end
  end
end
