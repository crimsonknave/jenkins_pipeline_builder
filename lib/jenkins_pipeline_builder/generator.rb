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
  class Generator
    include GeneratorSharedMethods

    attr_reader :debug
    attr_accessor :no_files, :job_templates, :job_collection, :module_registry, :remote_depends

    def initialize
      @job_templates = {}
      @job_collection = {}
      @extensions = {}
      @remote_depends = {}
      @module_registry = ModuleRegistry.new
    end

    def debug=(value)
      @debug = value
      logger.level = (value) ? Logger::DEBUG : Logger::INFO
    end

    def client
      JenkinsPipelineBuilder.client
    end

    def view
      JenkinsPipelineBuilder::View.new(self)
    end

    def bootstrap(path, project_name = nil)
      logger.info "Bootstrapping pipeline from path #{path}"
      load_collection_from_path(path)
      with_override
      cleanup_temp_remote
      errors = {}
      if projects.any?
        errors = publish_project(project_name)
      else
        errors = publish_jobs(standalone jobs)
      end
      errors.each do |k, v|
        logger.error "Encountered errors compiling: #{k}:"
        logger.error v
      end
      errors
    end

    def pull_request(path, project_name)
      failed = false
      logger.info "Pull Request Generator Running from path #{path}"
      load_collection_from_path(path)
      cleanup_temp_remote
      logger.info "Project: #{projects}"
      projects.each do |project|
        next unless project[:name] == project_name || project_name.nil?
        failed = true unless PullRequestGenerator.new project
      end
      !failed
    end

    def file(path, project_name)
      logger.info "Generating files from path #{path}"
      @file_mode = true
      bootstrap(path, project_name)
    end

    def dump(job_name)
      logger.info "Debug #{@debug}"
      logger.info "Dumping #{job_name} into #{job_name}.xml"
      xml = client.job.get_config(job_name)
      File.open(job_name + '.xml', 'w') { |f| f.write xml }
    end

    private

    # Converts standalone jobs to the format that they have when loaded as part of a project.
    # This addresses an issue where #pubish_jobs assumes that each job will be wrapped
    # with in a hash a referenced under a key called :result, which is what happens when
    # it is loaded as part of a project.
    #
    # @return An array of jobs
    #
    def standalone(jobs)
      { value: { jobs: jobs.map! { |job| { result: job } } } }
    end

    def load_job_collection(yaml, remote = false)
      yaml.each do |section|
        Utils.symbolize_keys_deep!(section)
        key = section.keys.first
        value = section[key]
        if key == :dependencies
          logger.info 'Resolving Dependencies for remote project'
          load_remote_files(value)
          next
        end
        name = value[:name]
        if job_collection.key?(name)
          if remote
            logger.info "Duplicate item with name '#{name}' was detected from the remote folder."
          else
            fail "Duplicate item with name '#{name}' was detected."
          end
        else
          job_collection[name.to_s] = { name: name.to_s, type: key, value: value }
        end
      end
    end

    def process_resolution_errors(errors)
      errors.each do |k, v|
        puts "Encountered errors processing: #{k}:"
        v.each do |key, error|
          puts "  key: #{key} had the following error:"
          puts "  #{error.inspect}"
        end
      end
    end

    def process_jobs_and_views(project)
      project_body = project[:value]
      jobs = prepare_jobs(project_body[:jobs]) if project_body[:jobs]
      logger.info project
      process_job_changes(jobs)
      errors = process_jobs(jobs, project)
      errors = process_views(project_body[:views], project, errors) if project_body[:views]
      errors
    end

    def resolve_project(project)
      defaults = find_defaults
      settings = defaults.nil? ? {} : defaults[:value] || {}
      project[:settings] = Compiler.get_settings_bag(project, settings) unless project[:settings]

      errors = process_jobs_and_views project
      process_resolution_errors errors
      return false, 'Encountered errors exiting' unless errors.empty?

      [true, project]
    end

    def check_job(job)
      fail 'Job name is not specified' unless job[:name]

      job[:job_type] ||= 'free_style'
      supported_job_types = %w(job_dsl multi_project build_flow free_style pull_request_generator)
      unless supported_job_types.include? job[:job_type]
        return false, "Job type: #{job[:job_type]} is not one of job_dsl, multi_project, build_flow or free_style"
      end

      job
    end

    def adjust_multi_project(xml)
      n_xml = Nokogiri::XML(xml)
      root = n_xml.root
      root.name = 'com.tikal.jenkins.plugins.multijob.MultiJobProject'
      n_xml.to_xml
    end

    def compile_freestyle_job_to_xml(params)
      params = extract_template_params(params)

      xml = client.job.build_freestyle_config(params)
      n_xml = Nokogiri::XML(xml, &:noblanks)

      logger.debug 'Loading the required modules'
      @module_registry.traverse_registry_path('job', params, n_xml)
      logger.debug 'Module loading complete'

      n_xml.to_xml
    end

    def extract_template_params(params)
      if params.key?(:template)
        template_name = params[:template]
        fail "Job template '#{template_name}' can't be resolved." unless @job_templates.key?(template_name)
        params.delete(:template)
        template = @job_templates[template_name]
        puts "Template found: #{template}"
        params = template.deep_merge(params)
        puts "Template merged: #{template}"
      end

      params
    end

    def add_job_dsl(job, xml)
      n_xml = Nokogiri::XML(xml)
      n_xml.root.name = 'com.cloudbees.plugins.flow.BuildFlow'
      Nokogiri::XML::Builder.with(n_xml.root) do |b_xml|
        b_xml.dsl job[:build_flow]
      end
      n_xml.to_xml
    end

    # TODO: make sure this is tested
    def update_job_dsl(job, xml)
      n_xml = Nokogiri::XML(xml)
      n_builders = n_xml.xpath('//builders').first
      Nokogiri::XML::Builder.with(n_builders) do |b_xml|
        build_job_dsl(job, b_xml)
      end
      n_xml.to_xml
    end

    def generate_job_dsl_body(params)
      logger.info 'Generating pipeline'

      xml = client.job.build_freestyle_config(params)

      n_xml = Nokogiri::XML(xml)
      if n_xml.xpath('//javaposse.jobdsl.plugin.ExecuteDslScripts').empty?
        p_xml = Nokogiri::XML::Builder.new(encoding: 'UTF-8') do |b_xml|
          build_job_dsl(params, b_xml)
        end

        n_xml.xpath('//builders').first.add_child("\r\n" + p_xml.doc.root.to_xml(indent: 4) + "\r\n")
        xml = n_xml.to_xml
      end
      xml
    end

    def expand_job(job)
      new_jobs = []
      job_name = job.keys.first
      overrides = job[job_name][:with_overrides]
      overrides.each do |override|
        clone = Marshal.load(Marshal.dump(job))
        clone[job_name].delete :with_overrides
        clone[job_name] = clone[job_name].merge override
        new_jobs << clone
      end
      new_jobs
    end

    def with_override
      job_collection.each do |_, v|
        new_jobs = []
        removes = []
        next unless v[:value][:jobs]
        job_set = v[:value][:jobs]
        job_set.each do |job|
          next unless job.is_a?(Hash)
          job_name = job.keys.first
          next unless job[job_name][:with_overrides]
          new_jobs.concat expand_job(job)
          removes << job
        end
        job_set.delete_if { |x| removes.include? x }
        job_set.concat new_jobs
      end
    end

    def build_job_dsl(job, xml)
      xml.send('javaposse.jobdsl.plugin.ExecuteDslScripts') do
        if job.key?(:job_dsl)
          xml.scriptText job[:job_dsl]
          xml.usingScriptText true
        else
          xml.targets job[:job_dsl_targets]
          xml.usingScriptText false
        end
        xml.ignoreExisting false
        xml.removedJobAction 'IGNORE'
      end
    end

    def out_dir
      'out/xml'
    end

    def projects
      result = []
      job_collection.values.each do |item|
        result << item if item[:type] == :project
      end
      result
    end

    def jobs
      result = []
      job_collection.values.each do |item|
        result << item if item[:type] == :job
      end
      result
    end

    def publish_project(project_name, errors = {})
      projects.each do |project|
        next unless project_name.nil? || project[:name] == project_name
        success, payload = resolve_project(project)
        if success
          logger.info 'successfully resolved project'
          compiled_project = payload
        else
          return { project_name: 'Failed to resolve' }
        end

        errors = publish_jobs compiled_project
        publish_views compiled_project
      end
      errors
    end

    def publish_views(project)
      views = project[:value][:views]
      return unless views
      views.each do |v|
        compiled_view = v[:result]
        view.create(compiled_view)
      end
    end

    def publish_jobs(project, errors = {})
      jobs = project[:value][:jobs]
      return unless jobs
      jobs.each do |i|
        logger.info "Processing #{i}"
        job = i[:result]
        fail "Result is empty for #{i}" if job.nil?
        success, payload = compile_job_to_xml(job)
        if success
          create_or_update(job, payload)
        else
          errors[job[:name]] = payload
        end
      end
      errors
    end

    def create_or_update(job, xml)
      job_name = job[:name]
      if @debug || @file_mode
        write_jobs job, xml
        return
      end

      if client.job.exists?(job_name)
        client.job.update(job_name, xml)
      else
        client.job.create(job_name, xml)
      end
    end

    def write_jobs(job, xml)
      logger.info "Will create job #{job}"
      logger.info "#{xml}" if @debug
      FileUtils.mkdir_p(out_dir) unless File.exist?(out_dir)
      File.open("#{out_dir}/#{job[:name]}.xml", 'w') { |f| f.write xml }
    end

    def compile_job_to_xml(job)
      job = check_job job

      logger.info "Creating Yaml Job #{job}"
      payload = compile_freestyle_job_to_xml job

      case job[:job_type]
      when 'job_dsl'
        payload = update_job_dsl job, payload
      when 'multi_project'
        payload = adjust_multi_project payload
      when 'build_flow'
        payload = add_job_dsl job, payload
      end

      [true, payload]
    end

    def cleanup_temp_remote
      @remote_depends.each_value do |file|
        FileUtils.rm_r file
        FileUtils.rm_r "#{file}.tar"
      end
    end

    def list_plugins
      client.plugin.list_installed
    end

    def prepare_jobs(jobs)
      jobs.map! do |job|
        job.is_a?(String) ? { job.to_sym => {} } : job
      end
    end

    def process_job_changes(jobs)
      jobs.each do |job|
        job_id = job.keys.first
        j = get_item(job_id)

        next unless j

        Utils.hash_merge!(j, job[job_id])
        j[:value][:name] = j[:job_name] if j[:job_name]
      end
    end

    def process_views(views, project, errors = {})
      views.map! do |view|
        view.is_a?(String) ? { view.to_sym => {} } : view
      end
      views.each do |view|
        view_id = view.keys.first
        settings = project[:settings].clone.merge(view[view_id])
        # TODO: rename resolve_job_by_name properly
        success, payload = resolve_job_by_name(view_id, settings)
        if success
          view[:result] = payload
        else
          errors[view_id] = payload
        end
      end
      errors
    end

    def process_jobs(jobs, project, errors = {})
      jobs.each do |job|
        job_id = job.keys.first
        settings = project[:settings].clone.merge(job[job_id])
        success, payload = resolve_job_by_name(job_id, settings)
        if success
          job[:result] = payload
        else
          errors[job_id] = payload
        end
      end
      errors
    end

    def find_defaults
      job_collection.each_value do |item|
        return item if item[:type] == 'defaults' || item[:type] == :defaults
      end
      # This is here for historical purposes
      get_item('global')
    end

    def load_latest_template!(path, template)
      folders = Dir.entries(path)
      highest = folders.max
      template[:version] = highest unless highest == 0
    end

    def load_remote_collection_from_path(path)
      if File.directory?(path)
        logger.info "Loading from #{path}"
        load_collection_from_path(path, true)
        true
      else
        false
      end
    end

    def use_newest_template_verson?(path, template)
      (template[:version].nil? || template[:version] == 'newest') && File.directory?(path)
    end

    def find_remote_template_path(path, template)
      path = File.join(path, template[:name]) unless template[:name] == 'default'
      # If we are looking for the newest version or no version was set
      if use_newest_template_verson? path, template
        load_latest_template! path, template
      end
      path = File.join(path, template[:version]) unless template[:version].nil?
      path = File.join(path, 'pipeline')
      path
    end

    def load_template(path, template)
      # If we specify what folder the yaml is in, load that
      if template[:folder]
        path = File.join(path, template[:folder])
      else
        path = find_remote_template_path path, template
      end

      load_remote_collection_from_path path
    end

    def download_yaml(url, file, remote_opts = {})
      @remote_depends[url] = file
      logger.info "Downloading #{url} to #{file}.tar"
      open("#{file}.tar", 'w') do |local_file|
        open(url, remote_opts) do |remote_file|
          local_file.write(Zlib::GzipReader.new(remote_file).read)
        end
      end

      # Extract Tar.gz to 'remote' folder
      logger.info "Unpacking #{file}.tar to #{file} folder"
      Archive::Tar::Minitar.unpack("#{file}.tar", file)
    end

    def load_remote_files(dependencies)
      ### Load remote YAML
      # Download Tar.gz
      dependencies.each do |source|
        source = source[:source]
        url = source[:url]

        file = "remote-#{@remote_depends.length}"
        if @remote_depends[url]
          file = @remote_depends[url]
        else
          opts = {}
          opts = { ssl_verify_mode: OpenSSL::SSL::VERIFY_NONE } if source[:verify_ssl] == false
          download_yaml(url, file, opts)
        end

        path = File.expand_path(file, Dir.getwd)
        # Load templates recursively
        unless source[:templates]
          logger.info 'No specific template specified'
          # Try to load the folder or the pipeline folder
          path = File.join(path, 'pipeline') if Dir.entries(path).include? 'pipeline'
          return load_collection_from_path(path)
        end

        load_templates(path, source[:templates])
      end
    end

    def load_templates(path, templates)
      templates.each do |template|
        version = template[:version] || 'newest'
        logger.info "Loading #{template[:name]} at version #{version}"
        # Move into the remote folder and look for the template folder
        remote = Dir.entries(path)
        if remote.include? template[:name]
          # We found the template name, load this path
          logger.info 'We found the template!'
          load_template(path, template)
        else
          # Many cases we must dig one layer deep
          remote.each do |file|
            load_template(File.join(path, file), template)
          end
        end
      end
    end

    def load_extensions(path)
      path = "#{path}/extensions"
      path = File.expand_path(path, Dir.getwd)
      return unless File.directory?(path)
      logger.info "Loading extensions from folder #{path}"
      logger.info Dir.glob("#{path}/*.rb").inspect
      Dir.glob("#{path}/*.rb").each do |file|
        logger.info "Loaded #{file}"
        require file
      end
    end

    def load_json_file(file, remote)
      logger.info "Loading file #{file}"
      json = JSON.parse(IO.read(file))
      load_job_collection(json, remote)
    end

    def load_yaml_file(file, remote)
      logger.info "Loading file #{file}"
      yaml = YAML.load_file(file)
      load_job_collection(yaml, remote)
    end

    def load_collection_from_folder(path, remote)
      logger.info "Generating from folder #{path}"
      Dir[File.join(path, '/*.{yaml,yml}')].each do |file|
        load_yaml_file file, remote
      end
      Dir[File.join(path, '/*.json')].each do |file|
        load_json_file file, remote
      end
    end

    def load_collection_from_path(path, remote = false)
      load_extensions(path)
      path = File.expand_path(path, Dir.getwd)
      if File.directory?(path)
        load_collection_from_folder path, remote
      else
        logger.info "Loading file #{path}"
        if path.end_with? 'json'
          hash = JSON.parse(IO.read(path))
        else  # elsif path.end_with?("yml") || path.end_with?("yaml")
          hash = YAML.load_file(path)
        end
        load_job_collection(hash, remote)
      end
    end
  end
end
