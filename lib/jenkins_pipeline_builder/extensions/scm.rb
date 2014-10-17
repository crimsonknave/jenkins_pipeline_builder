scm_type do
  name :git
  plugin_id 'git'
  version '0' do

    xml do
      scm class: 'hudson.plugins.git.GitSCM' do
        foo 'asdf'
      end
    end
  end
end
