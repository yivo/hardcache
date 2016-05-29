module HardCache
  module Extension
    extend ActiveSupport::Concern

    included do
      cattr_accessor :hardcache_namespaces, instance_writer: false, instance_reader: false
      cattr_accessor :hardcache_hook_defined, instance_writer: false, instance_reader: false

      self.hardcache_namespaces = []
      self.hardcache_hook_defined = false
    end

    module ClassMethods
      def hardcache(namespace, cache_instances = true, &block)
        @hardcache ||= {}
        ns    = namespace
        cache = @hardcache[ns]
        key   = hardcache_version_key(ns)
        fresh = cache && cache[:records] && cache[:version] &&
                (ver = $redis.get(key)) && ver == cache[:version]

        if not fresh
          @hardcache[ns] = (cache ||= {})

          Rails.logger.info "[RecordsCache] Querying #{name}"

          cache[:records] = uncached { block ? instance_eval(&block) : all }.to_a
          cache[:version] = cache[:records].map(&:cache_key).join('/')

          unless cache_instances
            cache[:records].map! { |ar| ar.respond_to?(:to_hash) ? ar.to_hash : ar.as_json }
          end

          $redis.set(key, cache[:version])
        end

        unless hardcache_hook_defined
          hardcache_namespaces << ns # TODO Fix

          traits.inheritance_chain[0].after_commit do
            traits.inheritance_chain.each(&:flush_hardcache)
          end
          self.hardcache_hook_defined = true
        end

        unless cache_instances
          zero_class = traits.inheritance_chain[0]
          cache[:records].map { |attrs| zero_class.new(attrs) }
        else
          cache[:records].each(&:clear_association_cache)
          cache[:records]
        end
      end

      def flush_hardcache
        Rails.logger.info "[RecordsCache] Flushing cached records for #{name}"
        @hardcache = nil
        keys = hardcache_namespaces.map { |ns| hardcache_version_key(ns) }
        $redis.del(keys) unless keys.empty?
        nil
      end

    private
      def hardcache_version_key(ns)
        "#{name.underscore}:hardcache:#{ns}:version"
      end
    end
  end
end
