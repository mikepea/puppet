require 'puppet/util/cacher'

# Just define it, so this class has fewer load dependencies.
class Puppet::Node
end

# Model the environment that a node can operate in.  This class just
# provides a simple wrapper for the functionality around environments.
class Puppet::Node::Environment
    module Helper
        def environment
            Puppet::Node::Environment.new(@environment)
        end

        def environment=(env)
            if env.is_a?(String) or env.is_a?(Symbol)
                @environment = env
            else
                @environment = env.name
            end
        end
    end

    include Puppet::Util::Cacher

    @seen = {}

    # Return an existing environment instance, or create a new one.
    def self.new(name = nil)
        return name if name.is_a?(self)
        name ||= Puppet.settings.value(:environment)

        raise ArgumentError, "Environment name must be specified" unless name

        symbol = name.to_sym

        return @seen[symbol] if @seen[symbol]

        obj = self.allocate
        obj.send :initialize, symbol
        @seen[symbol] = obj
    end

    def self.current
        Thread.current[:environment] || root
    end

    def self.current=(env)
        Thread.current[:environment] = new(env)
    end

    def self.root
        @root
    end

    # This is only used for testing.
    def self.clear
        @seen.clear
    end

    attr_reader :name

    # Return an environment-specific setting.
    def [](param)
        Puppet.settings.value(param, self.name)
    end

    def initialize(name)
        @name = name
    end

    def known_resource_types
        if @known_resource_types.nil? or @known_resource_types.stale?
            @known_resource_types = Puppet::Resource::TypeCollection.new(self)
            @known_resource_types.perform_initial_import
        end
        @known_resource_types
    end

    def module(name)
        mod = Puppet::Module.new(name, self)
        return nil unless mod.exist?
        return mod
    end

    # Cache the modulepath, so that we aren't searching through
    # all known directories all the time.
    cached_attr(:modulepath, :ttl => Puppet[:filetimeout]) do
        dirs = self[:modulepath].split(File::PATH_SEPARATOR)
        if ENV["PUPPETLIB"]
            dirs = ENV["PUPPETLIB"].split(File::PATH_SEPARATOR) + dirs
        end
        validate_dirs(dirs)
    end

    # Return all modules from this environment.
    # Cache the list, because it can be expensive to create.
    cached_attr(:modules, :ttl => Puppet[:filetimeout]) do
        module_names = modulepath.collect { |path| Dir.entries(path) }.flatten.uniq
        module_names.collect do |path|
            begin
                Puppet::Module.new(path, self)
            rescue Puppet::Module::Error => e
                nil
            end
        end.compact
    end

    # Cache the manifestdir, so that we aren't searching through
    # all known directories all the time.
    cached_attr(:manifestdir, :ttl => Puppet[:filetimeout]) do
        validate_dirs(self[:manifestdir].split(File::PATH_SEPARATOR))
    end

    def to_s
        name.to_s
    end

    def validate_dirs(dirs)
        dirs.collect do |dir|
            if dir !~ /^#{File::SEPARATOR}/
                File.join(Dir.getwd, dir)
            else
                dir
            end
        end.find_all do |p|
            p =~ /^#{File::SEPARATOR}/ && FileTest.directory?(p)
        end
    end

    @root = new(:'*root*') 
end
