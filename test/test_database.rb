
require_relative '../app/database'
require_relative '../app/profile'
require "test/unit"

module Antiblog
  class TestDatabase < Test::Unit::TestCase
    def setup
      Profile.init_mock
      Database.init
      @db = Database
    end

    def teardown
    end

    MinimalEntry = {
      'body' => 'Hello, world',
      'signature' => 'sig1'
    }

    TitledEntry = MinimalEntry.merge({
      'title' => "Some title",
      'signature' => "sig2"
    })

    TaggedEntry = MinimalEntry.merge({
      'tags' => ['stuff'],
      'signature' => 'sig3'
    })

    SymlinkedEntry = MinimalEntry.merge({
      'symlink' => 'foobar',
      'signature' => 'sig4'
    })

    TeasedEntry = MinimalEntry.merge({
      'summary' => 'Some summary',
      'signature' => 'sig4'
    })

    LongEntry = {
      'body' => 'Hello ' * 1000,
      'signature' => 'sig5'
    }

    SerialEntry_1 = {
      'body' => "Hello, world",
      'series' => [{'series' => 'the_story', 'index' => 1}],
      'signature' => 'sig6'
    }

    SerialEntry_2 = {
      'body' => "Hello, world",
      'series' => [{'series' => 'the_story', 'index' => 2}],
      'symlink' => 'foo',
      'signature' => 'sig7'
    }

    SerialEntry_3 = {
      'body' => "Hello, world",
      'series' => [{'series' => 'the_story', 'index' => 3}],
      'metalink' => 'bar',
      'signature' => 'sig8'
    }

    MetalinkedEntry = MinimalEntry.merge({
      'metalink' => 'foobar',
      'signature' => 'sig9'
    })

    DualLinkedEntry = MinimalEntry.merge({
      'metalink' => 'foobar',
      'symlink' => 'barfoo',
      'signature' => 'sig10'
    })

    RedirectEntry = {
      'url' => 'http://example.com',
      'signature' => 'sig11'
    }

    BackupEntry = MinimalEntry.merge({
      'id' => 111222
    })

    def insert_minimal
      Database.create_entry(MinimalEntry)
    end

    def test_mock_profile
      assert(Antiblog::Profile.mock?)
      assert_equal(4000, Antiblog::Profile.http_port)
    end

    def test_create
      id = insert_minimal
      es = @db.entry_locals(id.to_s).entries
      assert_equal(1, es.length)
      assert_equal("Hello, world", es[0].content)
      assert_equal("##{id}", es[0]['title'])
      assert_equal(id, es[0].id)
    end

    def test_update
      id = insert_minimal
      changed = MinimalEntry.merge({
        'body' => 'Hello world again',
        'id' => id
      })
      Database.update_entry(changed)
      es = Database.entry_locals(id.to_s).entries
      assert_equal(1, es.length)
      assert_equal("Hello world again", es[0].content)
    end

    def test_id_by_ref
      context = Domain::Context.new
      id = @db.id_by_ref('foobar', context)
      assert_equal(nil, id)
      id = insert_minimal
      id2 = @db.id_by_ref(id.to_s, context)
      assert_equal(id, id2)
    end

    def test_entry_locals
      id = insert_minimal
      es = @db.entry_locals(id.to_s).entries
      assert_equal(1, es.length)
      assert_equal("Hello, world", es[0].content)
      assert_equal("##{id}", es[0]['title'])
      assert_equal("/entry/#{id}", es[0]['permalink'])
    end

    def test_create_with_title
      id = @db.create_entry TitledEntry
      es = @db.entry_locals(id.to_s).entries
      assert_equal(1, es.length)
      assert_equal("Some title", es[0]['title'])
    end

    def test_page_ref
      ref = Domain::PageRef.new(nil, 2)
      assert_nil(ref.tag)
      assert_equal(2, ref.index)
      assert_equal('/page/2', ref.url)

      ref = Domain::PageRef.make
      assert_equal(1, ref.index)
      assert_equal(nil, ref.tag)
      nx = ref.next(2)
      assert_equal('/page/2', nx)

      ref = Domain::PageRef.make '1'
      assert_equal(1, ref.index)
      assert_equal(nil, ref.tag)

      ref = Domain::PageRef.make('2', nil)
      assert_equal(2, ref.index)
      assert_equal(nil, ref.tag)

      ref = Domain::PageRef.make('foobar', nil)
      assert_equal(1, ref.index)
      assert_equal('foobar', ref.tag)

      ref = Domain::PageRef.make('barfoo', '2')
      assert_equal(2, ref.index)
      assert_equal('barfoo', ref.tag)

      ref = Domain::PageRef.make 'last'
      assert_equal(:last, ref.index)
      assert_equal(nil, ref.tag)

      ref = Domain::PageRef.make('foo', 'last')
      assert_equal(:last, ref.index)
      assert_equal('foo', ref.tag)
    end

    def test_page_locals
      vars = @db.page_locals
      assert_equal(0, vars.entries.length)
      id = insert_minimal
      vars = @db.page_locals
      es = vars.entries
      assert_equal(1, es.length)
      assert_equal(id, es[0].id)
      assert_equal("Hello, world", es[0].content)
      assert_equal(false, vars.entries[0]['read_more'])
      6.times { insert_minimal }
      vars = @db.page_locals
      assert_equal(5, vars.entries.length)
      vars = @db.page_locals(ref = '2')
      assert_equal(2, vars.entries.length)
      vars = @db.page_locals(ref = '3')
      assert_equal(0, vars.entries.length)
    end

    def test_tags
      id = Database.create_entry TaggedEntry
      es = Database.entry_locals(id.to_s).entries
      assert_equal(1, es.length)
      assert_equal(['micro', 'stuff'], es[0]['tags'].to_liquid)
      assert_equal(['micro', 'stuff'], es[0].to_h['tags'].to_liquid)
    end

    def test_no_tags
      id = @db.create_entry LongEntry
      es = @db.entry_locals(id.to_s).entries
      assert_equal(1, es.length)
      assert_nil(es[0].tags.to_liquid)
    end

    def test_tag_cloud
      id = Database.create_entry(TaggedEntry)
      tc = Database.entry_locals(id.to_s).tag_cloud
      assert_equal(2, tc.length)
      assert_equal({ 'name' => 'micro', 'count' => 1, 'color' => 2 }, tc[0])
      assert_equal({ 'name' => 'stuff', 'count' => 1, 'color' => 2 }, tc[1])
      #
      Antiblog::Profile.init_mock(has_micro: false)
      tc = Database.entry_locals(id.to_s).tag_cloud
      assert_equal(1, tc.length)
      assert_equal({ 'name' => 'stuff', 'count' => 1, 'color' => 2 }, tc[0])    
    end

    def test_index
      id = insert_minimal
      index = @db.api_index
      assert_equal(1, index.length)
      assert_equal({:id => id, :signature => 'sig1'}, index[0])
    end

    def test_symlink
      ida = Database.create_entry(SymlinkedEntry)
      es = Database.entry_locals(ida.to_s).entries
      assert_equal(1, es.length)
      assert_equal('/entry/foobar', es[0]['permalink'])

      es = Database.page_locals.entries
      assert_equal(1, es.length)
      assert_equal('/entry/foobar', es[0]['permalink'])

      idb = Database.create_entry(MinimalEntry)
      es = Database.entry_locals(idb.to_s).entries
      assert_equal(1, es.length)
      assert_equal("/entry/#{idb}", es[0]['permalink'])

      es = Database.page_locals.entries
      assert_equal(2, es.length)

      if es[0].id == ida then
        a = es[0]
        b = es[1]
      else
        a = es[1]
        b = es[0]
      end
      assert_equal(idb, b.id)
      assert_equal('/entry/foobar', a['permalink'])
      assert_equal("/entry/#{idb}", b['permalink'])
    end

    def test_metalink
      ida = @db.create_entry MetalinkedEntry
      vars = @db.entry_locals(ida.to_s)
      es = vars.entries
      assert_equal(1, es.length)
      assert_equal('/meta/foobar', es[0]['permalink'])
      assert_equal(['meta', 'micro'], es[0]['tags'].to_liquid)
      tc = vars.tag_cloud
      assert_equal('meta', tc[0]['name'])
      assert_equal('micro', tc[1]['name'])

      es = @db.page_locals.entries
      assert_equal(1, es.length)
      assert_equal('/meta/foobar', es[0]['permalink'])

      es = @db.page_locals("meta").entries
      assert_equal(1, es.length)
      assert_equal('/meta/foobar', es[0]['permalink'])
    end

    def test_dual_link
      @db.create_entry DualLinkedEntry
      es = @db.page_locals.entries
      assert_equal(1, es.length)
      assert_equal('/entry/barfoo', es[0]['permalink'])

      es = @db.page_locals('meta').entries
      assert_equal(1, es.length)
      assert_equal('/meta/foobar', es[0]['permalink'])

      es = @db.meta_locals('foobar').entries
      assert_equal(1, es.length)
      assert_equal('/meta/foobar', es[0]['permalink'])
    end

    def test_tag_page
      ida = Database.create_entry(TaggedEntry)
      idb = Database.create_entry(MinimalEntry)
      es = Database.page_locals('stuff').entries
      assert_equal(1, es.length)
      assert_equal(ida, es[0].id)
    end

    def test_random
      vars = @db.entry_locals('random')
      assert_nil(vars.redirect_url)
      assert(vars.empty?)

      ida = @db.create_entry MinimalEntry
      idb = @db.create_entry TitledEntry
      idc = @db.create_entry TaggedEntry
      vars = @db.entry_locals('random') do |ctx|
        # ctx.root_url = 'http://example.com'
      end
      assert_not_nil(vars.redirect_url)
      r = vars.redirect_url
      assert(r == "http://example.com/entry/#{ida}" ||
        r == "http://example.com/entry/#{idb}" ||
        r == "http://example.com/entry/#{idc}"
      )
    end

    def test_entry_count
      @db.create_entry MinimalEntry
      @db.create_entry TitledEntry
      @db.create_entry TaggedEntry
      @db.create_entry TeasedEntry
      v = Database::Base.entry_count
      assert_equal(4, v)
      v = Database::Base.entry_count('stuff')
      assert_equal(1, v)
      v = Database::Base.entry_count('micro')
      assert_equal(3, v)
      v = Database::Base.entry_count('foobar')
      assert_equal(0, v)
    end

    def test_prev_next
      11.times do
        @db.create_entry MinimalEntry
      end
      6.times do
        @db.create_entry TaggedEntry
      end
      vars = @db.page_locals
      assert_nil(vars.prev)
      assert_equal('/page/2', vars.next)

      vars = @db.page_locals '2'
      assert_equal('/', vars.prev)
      assert_equal('/page/3', vars.next)

      vars = @db.page_locals '4'
      assert_equal('/page/3', vars.prev)
      assert_nil(vars.next)

      vars = @db.page_locals 'stuff'
      assert_nil(vars.prev)
      assert_equal('/page/stuff/2', vars.next)

      vars = @db.page_locals('stuff', '2')
      assert_equal('/page/stuff', vars.prev)
      assert_nil(vars.next)
    end

    def test_long_entry
      @db.create_entry LongEntry
      es = @db.page_locals.entries
      assert_equal(1, es.length)
      assert(es[0]['read_more'])
    end

    def test_entry_color
      10.times do
        id = @db.create_entry MinimalEntry
        vars = @db.entry_locals id.to_s
        e = vars.entries[0]
        assert_equal(id % 6 + 1, e.to_h['color'])
      end
    end

    def test_series
      ida = @db.create_entry SerialEntry_1
      idb = @db.create_entry SerialEntry_2
      idc = @db.create_entry SerialEntry_3
      idd = @db.create_entry MinimalEntry

      es = @db.entry_locals(idd.to_s).entries
      ss = es[0].series
      assert_equal(0, ss.length)

      es = @db.page_locals.entries
      es.each do |e|
        ss = e.series
        assert_equal(0, ss.length)
      end

      es = @db.entry_locals(ida.to_s).entries
      ss = es[0].series
      assert_equal(1, ss.length)
      assert_equal("/entry/#{ida}", ss[0]['first']['permalink'])
      assert_nil(ss[0]['prev'])
      assert_equal('/entry/foo', ss[0]['next']['permalink'])
      assert_equal('/meta/bar', ss[0]['last']['permalink'])

      es = @db.entry_locals(idb.to_s).entries
      ss = es[0].series
      assert_equal(1, ss.length)
      assert_equal("/entry/#{ida}", ss[0]['first']['permalink'])
      assert_equal("/entry/#{ida}", ss[0]['prev']['permalink'])
      assert_equal('/meta/bar', ss[0]['next']['permalink'])
      assert_equal('/meta/bar', ss[0]['last']['permalink'])

      es = @db.entry_locals(idc.to_s).entries
      ss = es[0].series
      assert_equal(1, ss.length)
      assert_equal("/entry/#{ida}", ss[0]['first']['permalink'])
      assert_equal('/entry/foo', ss[0]['prev']['permalink'])
      assert_nil(ss[0]['next'])
      assert_equal('/meta/bar', ss[0]['last']['permalink'])
    end

    def test_redirect
      id = @db.create_entry RedirectEntry
      vars = @db.entry_locals(id.to_s)
      assert_equal('http://example.com', vars.redirect_url)

      vars = @db.page_locals
      assert_equal(0, vars.entries.length)
    end

    def test_rotate
      @db.rotate

      4.times { @db.create_entry MinimalEntry }
      es = @db.page_locals.entries
      assert_equal(4, es.length)
      ids_a = es.map(&:id)
      @db.rotate
      es = @db.page_locals.entries
      assert_equal(4, es.length)
      ids_b = es.map(&:id)
      assert_not_equal(ids_a, ids_b)
      assert_equal(ids_a, ids_b.rotate)
    end

    def test_profile_vars
      vars = @db.page_locals.to_h
      assert_equal('Antiblog MOCK', vars['site_title'])
      assert_equal('Anonymous', vars['author_name'])
      assert_equal('http://geekyfox.net', vars['author_href'])
      assert_equal('http://example.com', vars['root_url'])
      assert(vars['has_powered_by'])
    end

    def test_rotate_invisible
      3.times { @db.create_entry MinimalEntry }
      2.times { @db.create_entry RedirectEntry }
      es = @db.page_locals.entries
      assert_equal(3, es.length)
      ids_a = es.map(&:id)
      es = @db.rss_feed_locals.entries
      assert_equal(0, es.length)
      9.times { @db.rotate }
      es = @db.page_locals.entries
      assert_equal(3, es.length)
      ids_b = es.map(&:id)
      assert_equal(ids_a, ids_b)
      es = @db.rss_feed_locals.entries
      assert_equal(3, es.length)
    end

    def test_backup
      es = @db.page_locals.entries
      assert_equal(0, es.length)
      @db.update_entry(BackupEntry)
      es = @db.page_locals.entries
      assert_equal(1, es.length)
      assert_equal(BackupEntry['id'], es[0].id)
    end
  end
end