#
# Copyright (c) 2014 Constant Contact
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#

module JenkinsPipelineBuilder
  class ModuleRegistry
    attr_accessor :registry, :registered_modules
    def initialize
      @registry = { job: {} }
    end

    def versions
      # Return a hash with a default of 1000 so that we'll get the newest in debug
      return Hash.new { |_| '1000.0' } if JenkinsPipelineBuilder.generator.debug
      @versions ||= JenkinsPipelineBuilder.client.plugin.list_installed
    end

    def clear_versions
      @versions = nil
    end

    def logger
      JenkinsPipelineBuilder.logger
    end

    # Ideally refactor this out to be derived from the registry,
    # but I'm lazy for now
    def entries
      {
        builders: '//builders',
        publishers: '//publishers',
        wrappers: '//buildWrappers',
        triggers: '//triggers'
      }
    end

    def register(prefix, set)
      name = prefix.pop
      root = prefix.inject(@registry, :[])
      root[name] = {} unless root[name]
      # TODO: Set installed version here

      if root[name][set.name]
        root[name][set.name].merge set
      else
        root[name][set.name] = set
      end
    end

    def get(path)
      parts = path.split('/')
      get_by_path_collection(parts, @registry)
    end

    def get_by_path_collection(path, registry)
      item = registry[path.shift.to_sym]
      return item if path.count == 0

      get_by_path_collection(path, item)
    end

    def traverse_registry_path(path, params, n_xml)
      registry = get(path)
      traverse_registry(registry, params, n_xml)
    end

    def traverse_registry(registry, params, n_xml, strict = false)
      params.each do |key, value|
        next unless registry.is_a? Hash
        unless registry.key? key
          fail "!!!! could not find key #{key} !!!!" if strict
          next
        end
        reg_value = registry[key]
        if reg_value.is_a? ExtensionSet
          use_extension_set reg_value, value, n_xml
        elsif value.is_a? Hash
          traverse_registry reg_value, value, n_xml, true
        elsif value.is_a? Array
          value.each do |v|
            traverse_registry reg_value, v, n_xml, true
          end
        end
      end
    end

    def execute_extension(extension, value, n_xml)
      n_builders = n_xml.xpath(extension.path).first
      n_builders.instance_exec(value, &extension.before) if extension.before
      Nokogiri::XML::Builder.with(n_builders) do |xml|
        xml.instance_exec value, &extension.xml
      end
      n_builders.instance_exec(value, &extension.after) if extension.after
      true
    end

    private

    def check_params(ext, value)
      params = ext.parameters
      return [] unless params == false || params.any?
      errors = []
      return [] unless value.is_a? Hash
      value.each_key do |key|
        next if params && params.include?(key)
        errors << "Extension #{extension.name} does not support parameter #{key}"
      end
      errors
    end

    def use_extension_set(registry_value, value, n_xml)
      ext = registry_value.extension
      logger.debug "Using #{ext.type} #{ext.name} version #{ext.min_version}"

      errors = check_params ext, value

      errors.each do |error|
        logger.error error
      end

      fail 'Encountered errors compiling the xml' if errors.any?

      execute_extension ext, value, n_xml
    end
  end
end
