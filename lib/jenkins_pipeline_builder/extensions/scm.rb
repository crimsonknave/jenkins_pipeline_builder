scm_type do
  name :git
  plugin_id 'git'
  version '0' do

    xml do |params|
      scm class: 'hudson.plugins.git.GitSCM' do
        configVersion 2
        userRemoteConfigs do
          name params[:name]
          refspec params[:refspec]
          url params[:url]
        end
        branches
        disableSubmodules
        doGenerateSubmoduleConfigurations
        authorOrCommitter
        clean
        pruneBranches
        remotePoll
        ignoreNotifyCommit
        useShallowClone
        buildChooser
        gitTool
        submoduleCfg
        relativeTargetDir
        reference
        excludedRegions
        excludedUsers
        gitConfigName
        gitConfigEmail
        skipTag
        includedRegions
        scmName
        localBranch
        recursiveSubmodules
        wipeOutWorkspace
      end
    end
  end
end
