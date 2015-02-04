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
        #failed = true unless generate_pull_request_jobs project
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
      jobs.map! { |job| { result: job } }
    end


  end
end
