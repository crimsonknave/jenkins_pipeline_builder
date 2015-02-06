require File.expand_path('../../spec_helper', __FILE__)

describe 'scm' do
  after :each do
    JenkinsPipelineBuilder.registry.clear_versions
  end

  before :all do
    JenkinsPipelineBuilder.credentials = {
      server_ip: '127.0.0.1',
      server_port: 8080,
      username: 'username',
      password: 'password',
      log_location: '/dev/null'
    }
  end

  before :each do
    builder = Nokogiri::XML::Builder.new { |xml| xml.project }
    @n_xml = builder.doc
  end

  after :each do |example|
    name = example.description.gsub ' ', '_'
    File.open("./out/xml/wrapper_#{name}.xml", 'w') { |f| @n_xml.write_xml_to f }
  end

  context 'git' do
    context 'v2.0' do
      before :each do
        JenkinsPipelineBuilder.registry.registry[:job][:scm][:git].installed_version = '2.0'
      end

      it 'generates correct xml structure' do
        JenkinsPipelineBuilder.registry.traverse_registry_path('job', { scm: { provider: :git } }, @n_xml)

        expect(@n_xml.at_css('scm')).to be_truthy
        expect(@n_xml.at_css('scm')['class']).to eq 'hudson.plugins.git.GitSCM'
        expect(@n_xml.at_css('scm configVersion').name).to eq 'configVersion'
        expect(@n_xml.at_css('scm configVersion').content).to eq '2'

        expect(@n_xml.at_css('scm userRemoteConfigs')).to be_truthy
        expect(@n_xml.at_css('scm branches')).to be_truthy
        expect(@n_xml.at_css('scm disableSubmodules')).to be_truthy
        expect(@n_xml.at_css('scm doGenerateSubmoduleConfigurations')).to be_truthy
        expect(@n_xml.at_css('scm authorOrCommitter')).to be_truthy
        expect(@n_xml.at_css('scm clean')).to be_truthy
        expect(@n_xml.at_css('scm pruneBranches')).to be_truthy
        expect(@n_xml.at_css('scm remotePoll')).to be_truthy
        expect(@n_xml.at_css('scm ignoreNotifyCommit')).to be_truthy
        expect(@n_xml.at_css('scm useShallowClone')).to be_truthy
        expect(@n_xml.at_css('scm buildChooser')).to be_truthy
        expect(@n_xml.at_css('scm gitTool')).to be_truthy
        expect(@n_xml.at_css('scm submoduleCfg')).to be_truthy
        expect(@n_xml.at_css('scm relativeTargetDir')).to be_truthy
        expect(@n_xml.at_css('scm reference')).to be_truthy
        expect(@n_xml.at_css('scm excludedRegions')).to be_truthy
        expect(@n_xml.at_css('scm excludedUsers')).to be_truthy
        expect(@n_xml.at_css('scm gitConfigName')).to be_truthy
        expect(@n_xml.at_css('scm gitConfigEmail')).to be_truthy
        expect(@n_xml.at_css('scm skipTag')).to be_truthy
        expect(@n_xml.at_css('scm includedRegions')).to be_truthy
        expect(@n_xml.at_css('scm scmName')).to be_truthy
        expect(@n_xml.at_css('scm localBranch')).to be_truthy
        expect(@n_xml.at_css('scm recursiveSubmodules')).to be_truthy
        expect(@n_xml.at_css('scm wipeOutWorkspace')).to be_truthy
      end

      context 'userRemoteConfigs' do
        let(:registry) { JenkinsPipelineBuilder.registry }

        it 'empty params' do
          registry.traverse_registry_path('job', { scm: { provider: :git } }, @n_xml)

          expect(@n_xml.at_css('scm userRemoteConfigs')).to be_truthy
          expect(@n_xml.at_css('scm userRemoteConfigs name').content).to eq ''
          expect(@n_xml.at_css('scm userRemoteConfigs refspec').content).to eq ''
          expect(@n_xml.at_css('scm userRemoteConfigs url').content).to eq ''
        end

        it 'name parameter' do
          registry.traverse_registry_path('job', { scm: { provider: :git, name: :foo } }, @n_xml)

          expect(@n_xml.at_css('scm userRemoteConfigs')).to be_truthy
          expect(@n_xml.at_css('scm userRemoteConfigs name').content).to eq 'foo'
        end

        it 'refspec' do
          registry.traverse_registry_path('job', { scm: { provider: :git, refspec: :foo } }, @n_xml)

          expect(@n_xml.at_css('scm userRemoteConfigs')).to be_truthy
          expect(@n_xml.at_css('scm userRemoteConfigs refspec').content).to eq 'foo'
        end

        it 'url' do
          registry.traverse_registry_path('job', { scm: { provider: :git, url: :foo } }, @n_xml)

          expect(@n_xml.at_css('scm userRemoteConfigs')).to be_truthy
          expect(@n_xml.at_css('scm userRemoteConfigs url').content).to eq 'foo'
        end
      end
    end
  end
end
