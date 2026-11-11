# frozen_string_literal: true
require 'net/http'
require 'json'
require 'uri'
module NevaehOs
  module WatchSensors
    module_function
    def snapshot(watcher)
      target=watcher.target
      case watcher.kind
      when 'ubuntu_package'
        UbuntuPackages.call(operation:'refresh') unless target['refresh']==false
        data=UbuntuPackages.call(operation:'show',package:target.fetch('package'))
        raise ArgumentError,'No Ubuntu candidate version is available' unless data['ubuntu_candidate'] && data['candidate'].present?
        {target['package']=>{'package'=>target['package'],'version'=>data['candidate']}}
      when 'ubuntu_catalog'
        UbuntuPackages.call(operation:'refresh') unless target['refresh']==false
        data=UbuntuPackages.call(operation:'catalog',package:target.fetch('query'))
        raise ArgumentError,'Catalog query exceeds 1000 matches; narrow the query before baselining' unless data['complete']==true
        data.fetch('packages').to_h { |p| [p.fetch('package'),{'package'=>p.fetch('package'),'version'=>p.fetch('version')}] }
      when 'ubuntu_sources'
        data=UbuntuPackages.call(operation:'sources')
        data.fetch('sources').to_h { |source| [source.fetch('identity'),source] }
      when 'github_repository'
        path="/repos/#{target.fetch('repository')}/branches/#{URI.encode_www_form_component(target.fetch('branch'))}"
        result=github_get(path,watcher)
        {target['repository']=>{'repository'=>target['repository'],'branch'=>target['branch'],'version'=>result.fetch('commit').fetch('sha')}}
      when 'github_account'
        owner=target.fetch('owner');prefix=target['account_type']=='organization' ? '/orgs/' : '/users/'
        private_user=target['account_type']=='user' && target['credential_slug'].present?
        if private_user
          identity=github_get('/user',watcher)
          raise ArgumentError,'Private user-account discovery requires a user token owned by the selected account' unless identity.fetch('login').casecmp?(owner)
        end
        rows=[]
        11.times do |index|
          type=target["account_type"]=="organization" ? "all" : "owner"
          path=private_user ? "/user/repos?affiliation=owner&per_page=100&page=#{index+1}&sort=full_name" : "#{prefix}#{owner}/repos?per_page=100&page=#{index+1}&sort=full_name&type=#{type}"
          page=github_get(path,watcher)
          raise ArgumentError,'Invalid GitHub repository catalog response' unless page.is_a?(Array)
          rows+=page
          raise ArgumentError,'Account exceeds 1000 accessible repositories; use individual repository watchers' if rows.length>1000
          break if page.length<100
        end
        rows.to_h do |repo|
          name=repo.fetch('full_name')
          raise ArgumentError,'Repository catalog returned an unexpected owner' unless name.split('/').first.casecmp?(owner)
          id=repo.fetch('id')
          raise ArgumentError,'Repository identity is invalid' unless id.is_a?(Integer) && id.positive?
          [id.to_s,{'repository'=>name,'branch'=>repo['default_branch'],'source'=>"https://github.com/#{name}"}]
        end
      else raise ArgumentError,'Unknown watcher sensor'
      end
    end
    def github_get(path,watcher)
      if watcher.target['credential_slug'].present?
        payload=LightekVault::Service.checkout!(slug:watcher.target['credential_slug'],consumer:'NevaehOs::WatchSensors',purpose:'nevaeh_repository_watch',requested_by:watcher.user.email_address)
        client=Gatekeeper::Hosting::GithubClient.new(payload)
        begin
          return client.call(:get,path)
        ensure
          client.close
        end
      end
      uri=URI('https://api.github.com'+path)
      request=Net::HTTP::Get.new(uri)
      request['Accept']='application/vnd.github+json';request['User-Agent']='Lightek-Nevaeh-Watcher';request['X-GitHub-Api-Version']='2022-11-28'
      response=Net::HTTP.start(uri.host,443,use_ssl:true,open_timeout:5,read_timeout:20) { |http| http.request(request) }
      raise ArgumentError,"GitHub watcher could not read the source (HTTP #{response.code}); check access and API rate limits" unless response.is_a?(Net::HTTPSuccess)
      raise ArgumentError,'GitHub response exceeded its size budget' if response.body.bytesize>2000000
      JSON.parse(response.body)
    rescue JSON::ParserError,SocketError,IOError,SystemCallError,Timeout::Error,OpenSSL::SSL::SSLError => error
      raise ArgumentError,"GitHub watcher is unavailable (#{error.class.name})"
    end
  end
end
