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
  class PullRequestGenerator
    include GeneratorSharedMethods
    attr_reader :purge
    attr_reader :create
    attr_reader :jobs

    def initialize(project)
      @purge = []
      @create = []

      logger.info "Using Project #{project}"
      pull_job = find_pull_request_generator(project)
      success, pull_job = compile_pull_request_generator(pull_job[:name], project)
      fail 'Unable to compile pull request' unless success
      @jobs = filter_pull_request_jobs(pull_job)

      pull_requests = check_for_pull pull_job
      purge_old(pull_requests, project)
      pull_requests.each do |number|
        # Manipulate the YAML
        req = JenkinsPipelineBuilder::PullRequest.new(project, number, jobs, pull_job)
        @jobs.merge! req.jobs
        project_new = req.project

        # Overwrite the jobs from the generator to the project
        project_new[:value][:jobs] = req.jobs.keys
        @create << project_new
      end
    end

    private

    def job_collection
      JenkinsPipelineBuilder.generator.job_collection
    end

    def generate_pull_request_jobs(project)
      pull = prepare_pull_request project
      job_collection.merge! pull.jobs
      success = create_pull_request_jobs(pull)
      return false unless success
      purge_pull_request_jobs(pull)
    end

    def purge_pull_request_jobs(pull)
      pull.purge.each do |purge_job|
        jobs = client.job.list "#{purge_job}.*"
        jobs.each do |job|
          client.job.delete job
        end
      end
    end

    def create_pull_request_jobs(pull)
      success = false
      pull.create.each do |pull_project|
        success, compiled_project = resolve_project(pull_project)
        compiled_project[:value][:jobs].each do |i|
          job = i[:result]
          success, payload = compile_job_to_xml(job)
          create_or_update(job, payload) if success
        end
      end
      success
    end

    def compile_pull_request_generator(pull_job, project)
      defaults = get_item('global')
      settings = defaults.nil? ? {} : defaults[:value] || {}
      settings = Compiler.get_settings_bag(project, settings)
      resolve_job_by_name(pull_job, settings)
    end

    def filter_pull_request_jobs(pull_job)
      jobs = {}
      pull_jobs = pull_job[:value][:jobs] || []
      pull_jobs.each do |job|
        if job.is_a? String
          jobs[job] = job_collection[job]
        else
          jobs[job.keys.first.to_s] = job_collection[job.keys.first.to_s]
        end
      end
      fail 'No jobs found for pull request' if jobs.empty?
      jobs
    end

    def find_pull_request_generator(project)
      project_jobs = project[:value][:jobs] || []
      puts '0--000000000000000'
      puts project_jobs
      puts '0--000000000000000'
      pull_job = nil
      project_jobs.each do |job|
        puts '1'
        job = job.keys.first if job.is_a? Hash
        puts job.inspect
        puts job_collection.inspect
        job = job_collection[job.to_s]
        puts "3: #{job.inspect}"
        pull_job = job if job[:value][:job_type] == 'pull_request_generator'
        puts '4'
        puts pull_job.inspect
      end
      fail 'No Pull Request Job Found for Project' unless pull_job
      pull_job
    end


    # Check for Github Pull Requests
    #
    # args[:git_url] URL to the github main page ex. https://www.github.com/
    # args[:git_repo] Name of repo only, not url  ex. jenkins_pipeline_builder
    # args[:git_org] The Orig user ex. constantcontact
    # @return = array of pull request numbers
    def check_for_pull(args)
      fail 'Please specify all arguments' unless args[:git_url] && args[:git_org] && args[:git_repo]
      # Build the Git URL
      git_url = "#{args[:git_url]}api/v3/repos/#{args[:git_org]}/#{args[:git_repo]}/pulls"

      # Download the JSON Data from the API
      resp = Net::HTTP.get_response(URI.parse(git_url))
      pulls = JSON.parse(resp.body)
      pulls.map { |p| p['number'] }
    end

    # Purge old builds
    def purge_old(pull_requests, project)
      reqs = pull_requests.clone.map { |req| "#{project[:name]}-PR#{req}" }
      # Read File
      old_requests = File.new('pull_requests.csv', 'a+').read.split(',')

      # Pop off current pull requests
      old_requests.delete_if { |req| reqs.include?("#{req}") }
      @purge = old_requests

      # Write File
      File.open('pull_requests.csv', 'w+') { |file| file.write reqs.join(',') }
    end
  end
end
