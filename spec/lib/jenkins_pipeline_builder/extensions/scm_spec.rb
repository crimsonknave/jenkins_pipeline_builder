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
    before :each do
      JenkinsPipelineBuilder.registry.registry[:job][:scm][:git].installed_version = '1.0'
    end

    it 'generates correct xml' do
      JenkinsPipelineBuilder.registry.traverse_registry_path('job', { scm: { provider: :git } }, @n_xml)

      node = @n_xml.root.xpath('//scm')
      expect(node.first).to be_truthy
      expect(node.first['class']).to eq 'hudson.plugins.git.GitSCM'
    end
  end
end
