module HardCache
  module Extension
    extend ActiveSupport::Concern

    module ClassMethods
      def hardcache(namespace, cache_instances = true, &block)
        @hardcache ||= {}
        ns    = namespace
        cache = @hardcache[ns]
        key   = hardcache_version_key(ns)
        fresh = cache && cache[:records] && cache[:version] &&
                (ver = Rails.cache.read(key)) && ver == cache[:version]

        if not fresh
          @hardcache[ns] = (cache ||= {})

          Rails.logger.info "[RecordsCache] Querying #{name}"

          cache[:records] = uncached { block ? instance_eval(&block) : all }.to_a
          cache[:version] = cache[:records].map(&:cache_key).join('/')

          unless cache_instances
            cache[:records].map! { |ar| ar.respond_to?(:to_hash) ? ar.to_hash : ar.as_json }
          end

          Rails.cache.write(key, cache[:version])
        end

        base = traits.inheritance_chain[0]
        unless base.instance_variable_get(:@hardcache_hook_defined)
          base.after_commit { base.flush_hardcache }
          base.instance_variable_set(:@hardcache_hook_defined, true)
        end

        @hardcache_namespaces ||= []
        @hardcache_namespaces << ns unless @hardcache_namespaces.include?(ns)

        unless cache_instances
          cache[:records].map { |attrs| base.new(attrs) }
        else
          cache[:records].each(&:clear_association_cache)
          cache[:records]
        end
      end

      def flush_hardcache
        keys = []
        traits.descendants.each do |ar|
          Rails.logger.info "[RecordsCache] Flushing cached records for #{ar.name}"
          ar.instance_eval do
            @hardcache = nil
            keys += @hardcache_namespaces if @hardcache_namespaces
          end
        end
        keys = keys.map { |ns| hardcache_version_key(ns) }
        Rails.cache.delete(keys) unless keys.empty?
        nil
      end

    private
      def hardcache_version_key(ns)
        "#{name.underscore}:hardcache:#{ns}:version"
      end
    end
  end
end
