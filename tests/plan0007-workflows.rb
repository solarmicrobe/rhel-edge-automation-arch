# Consumer-specific workflow and artifact reuse checks; no cluster actions.
require 'yaml'
require 'open3'
require 'tmpdir'
require 'fileutils'

WORKFLOW_ROOT = File.expand_path('..', __dir__)
WORKFLOW_NAMES = %w[composeImage stageImage publishOstree publishIso serveKickstarts]
WORKFLOW_GROUPS = {
  'composeImage' => %w[rfe-oci-image-pipeline rfe-oci-quay-repository rfe-oci-build-image rfe-oci-push-image],
  'stageImage' => %w[rfe-oci-stage-pipeline rfe-oci-stage-image],
  'publishOstree' => %w[rfe-oci-publish-content-pipeline rfe-oci-publish-content],
  'publishIso' => %w[rfe-oci-iso-pipeline rfe-oci-build-installer-image rfe-oci-build-auto-iso],
  'serveKickstarts' => %w[rfe-kickstart-pipeline upload-kickstart]
}
WORKFLOW_FAILURES = []
WORKFLOW_CHECKS = []

def workflow_render(chart, values = {}, succeeds: true, chart_root: File.join(WORKFLOW_ROOT, 'charts'), extra: [])
  Dir.mktmpdir do |dir|
    file = File.join(dir, 'values.yaml')
    File.write(file, values.empty? ? "{}\n" : YAML.dump(values))
    out, err, status = Open3.capture3('helm', 'template', chart, File.join(chart_root, chart), '-n', 'rfe', '-f', file, *extra)
    WORKFLOW_CHECKS << chart
    if status.success? != succeeds
      WORKFLOW_FAILURES << "#{chart}: expected success=#{succeeds}; values=#{values.inspect}; #{err}"
      return []
    end
    succeeds ? YAML.load_stream(out).compact : []
  end
end

def workflow_assert(condition, message)
  WORKFLOW_FAILURES << message unless condition
end

def workflow_values(active = [])
  { 'workflows' => WORKFLOW_NAMES.to_h { |name| [name, { 'enabled' => active.include?(name) }] } }
end

WORKFLOW_NAMES.each do |name|
  docs = workflow_render('rfe-pipelines', workflow_values([name]))
  resources = docs.select { |doc| %w[Pipeline Task].include?(doc['kind']) }
  workflow_assert(resources.map { |doc| doc.dig('metadata', 'name') }.sort == WORKFLOW_GROUPS[name].sort, "#{name} resource group")
  definitions = docs.select { |doc| doc['kind'] == 'Task' }.map { |doc| doc.dig('metadata', 'name') }
  docs.select { |doc| doc['kind'] == 'Pipeline' }.each do |pipeline|
    pipeline.dig('spec', 'tasks').each do |task|
      next unless task.dig('taskRef', 'kind') == 'Task'
      workflow_assert(definitions.include?(task.dig('taskRef', 'name')), "dangling local Task reference #{task.inspect}")
    end
  end
end

all_off = workflow_values
all_off['components'] = %w[registry pipelines imageBuilderVM httpd nexus virtualization].to_h { |name| [name, { 'mode' => 'disabled' }] }
%w[rfe-pipelines rbac].each { |chart| workflow_assert(workflow_render(chart, all_off).empty?, "all disabled still renders #{chart}") }

%w[rfe-pipelines rbac application-manager image-builder-vm].each do |chart|
  WORKFLOW_NAMES.each do |name|
    [0, '', 'false', nil].each do |invalid|
      workflow_render(chart, { 'workflows' => { name => { 'enabled' => invalid } } }, succeeds: false)
    end
  end
  [false, 0, '', nil].each do |invalid|
    workflow_render(chart, { 'workflows' => invalid }, succeeds: false)
    workflow_render(chart, { 'workflows' => { 'composeImage' => invalid } }, succeeds: false)
  end
end

stage = workflow_values(['stageImage']).merge(
  'rhelTarget' => { 'major' => 10, 'imageBuilder' => { 'enabled' => false } },
  'components' => {
    'registry' => { 'mode' => 'byo', 'connection' => { 'imagePath' => 'registry.example.com/rfe/edge', 'pullSecretName' => 'private-pull' } },
    'httpd' => { 'mode' => 'byo', 'connection' => { 'podNamespace' => 'staging', 'stageServiceAccountName' => 'existing-stage' } },
    'imageBuilderVM' => { 'mode' => 'disabled' }, 'nexus' => { 'mode' => 'disabled' }
  },
  'publicationEndpoints' => { 'registry' => { 'image' => { 'push' => false } }, 'httpServing' => { 'staging' => { 'create' => true } } }
)
stage_docs = workflow_render('rfe-pipelines', stage)
stage_pipeline = stage_docs.find { |doc| doc.dig('metadata', 'name') == 'rfe-oci-stage-pipeline' }
workflow_assert(stage_pipeline.dig('spec', 'params').find { |param| param['name'] == 'image-path' }['default'] == 'registry.example.com/rfe/edge', 'configured source image default lost')
rbac_docs = workflow_render('rbac', stage)
service_account = rbac_docs.find { |doc| doc['kind'] == 'ServiceAccount' && doc.dig('metadata', 'name') == 'existing-stage' }
workflow_assert(service_account && service_account.dig('metadata', 'namespace') == 'staging' && service_account['imagePullSecrets'] == [{ 'name' => 'private-pull' }], 'private stage pull Secret or service account targeting lost')
workflow_assert(rbac_docs.select { |doc| doc.dig('metadata', 'name').to_s.start_with?('oci-rfe-httpd') }.all? { |doc| doc.dig('metadata', 'namespace') == 'staging' }, 'staging grants use wrong namespace')
%w[external auto].each do |mode|
  values = stage.merge('permissions' => { 'mode' => mode }, 'deployment' => { 'mode' => 'byo-cluster-argocd' })
  workflow_assert(workflow_render('rbac', values).empty?, "#{mode} external permissions render owned objects")
end
public_stage = Marshal.load(Marshal.dump(stage))
public_stage.dig('components', 'registry', 'connection').delete('pullSecretName')
workflow_assert(workflow_render('rbac', public_stage).find { |doc| doc.dig('metadata', 'name') == 'existing-stage' }['imagePullSecrets'].nil?, 'public BYO stage requires publishing credential')
no_source_default = Marshal.load(Marshal.dump(public_stage))
no_source_default.dig('components', 'registry', 'connection').delete('imagePath')
workflow_render('rfe-pipelines', no_source_default) # Caller provides existing image-path and image-tag parameters.
workflow_assert(workflow_render('quay', { 'components' => { 'registry' => { 'mode' => 'byo' } } }).empty?, 'BYO read-only registry requires publisher connection')

content_httpd = {
  'mode' => 'byo',
  'connection' => { 'podNamespace' => 'serving', 'podLabelSelector' => 'app=serving', 'routeName' => 'serving', 'routeNamespace' => 'serving', 'webRoot' => '/srv/edge' }
}
%w[publishOstree serveKickstarts].each do |name|
  values = workflow_values([name]).merge(
    'components' => { 'httpd' => content_httpd, 'registry' => { 'mode' => 'disabled' }, 'imageBuilderVM' => { 'mode' => 'disabled' }, 'nexus' => { 'mode' => 'disabled' } },
    'publicationEndpoints' => { 'httpServing' => { 'content' => { 'write' => true } } }
  )
  docs = workflow_render('rfe-pipelines', values)
  workflow_assert(docs.none? { |doc| WORKFLOW_GROUPS['stageImage'].include?(doc.dig('metadata', 'name')) }, 'existing-stage publication still produces staging objects')
end
iso = workflow_values(['publishIso']).merge(
  'components' => { 'httpd' => content_httpd, 'registry' => { 'mode' => 'disabled' }, 'nexus' => { 'mode' => 'disabled' } },
  'publicationEndpoints' => { 'httpServing' => { 'content' => { 'write' => true } } }
)
iso_docs = workflow_render('rfe-pipelines', iso)
iso_pipeline = iso_docs.find { |doc| doc.dig('metadata', 'name') == 'rfe-oci-iso-pipeline' }
workflow_assert(%w[kickstart-url ostree-repo-url].all? { |name| iso_pipeline.dig('spec', 'params').any? { |param| param['name'] == name } }, 'ISO external artifact URL parameters lost')

# Both retained compose consumers require the existing BYO guest connection.
%w[composeImage publishIso].each do |name|
  workflow_render('rfe-pipelines', workflow_values([name]).merge('components' => { 'imageBuilderVM' => { 'mode' => 'byo' } }), succeeds: false)
  workflow_render('rfe-pipelines', workflow_values([name]).merge('rhelTarget' => { 'major' => 10 }), succeeds: false)
  workflow_render('rfe-pipelines', workflow_values([name]).merge('rhelTarget' => { 'imageBuilder' => { 'enabled' => false } }), succeeds: false)
end
workflow_render('rfe-pipelines', workflow_values(['composeImage']).merge('rhelTarget' => { 'imageBuilder' => { 'composeTypes' => { 'installer' => '' }, 'ostreeRef' => '' } }))
workflow_render('rfe-pipelines', workflow_values(['publishIso']).merge('rhelTarget' => { 'imageBuilder' => { 'composeTypes' => { 'container' => '' } } }))
workflow_render('rfe-pipelines', workflow_values(['publishOstree']).merge('rhelTarget' => { 'imageBuilder' => { 'enabled' => false, 'repositories' => [] } }))
workflow_render('rfe-pipelines', workflow_values(['publishOstree']).merge('rhelTarget' => { 'imageBuilder' => { 'ostreeRef' => 'rhel/9/x86_64/edge' } }), succeeds: false)

# Object-specific authorizations remain mandatory for each actual mutating consumer.
unauthorized_stage = Marshal.load(Marshal.dump(stage))
unauthorized_stage.dig('publicationEndpoints', 'httpServing', 'staging')['create'] = false
workflow_render('rfe-pipelines', unauthorized_stage, succeeds: false, extra: ['--show-only', 'templates/rfe-oci-stage-image-task.yaml'])
workflow_render('rfe-pipelines', iso.merge('publicationEndpoints' => { 'httpServing' => { 'content' => { 'write' => false } } }), succeeds: false)
workflow_render('rfe-pipelines', workflow_values(['composeImage']).merge('publicationEndpoints' => { 'registry' => { 'image' => { 'push' => false } } }), succeeds: false)

# Missing inactive connections are accepted, but malformed supplied values/flags always fail.
%w[rfe-pipelines rbac].each do |chart|
  [false, 0, '', 'bad/name'].each do |invalid|
    workflow_render(chart, workflow_values.merge('components' => { 'registry' => { 'connection' => { 'pullSecretName' => invalid } } }), succeeds: false)
  end
  workflow_render(chart, workflow_values.merge('publicationEndpoints' => { 'httpServing' => { 'staging' => { 'create' => 'false' } } }), succeeds: false)
  workflow_render(chart, workflow_values.merge('components' => { 'httpd' => { 'connection' => { 'webRoot' => '$(unsafe)' } } }), succeeds: false)
  workflow_render(chart, workflow_values.merge('components' => { 'imageBuilderVM' => { 'connection' => { 'host' => 'bad;command' } } }), succeeds: false)
end
%w[registry nexus httpd imageBuilderVM pipelines].each do |component|
  [false, 0, ''].each { |invalid| workflow_render('rfe-pipelines', workflow_values.merge('components' => { component => { 'mode' => invalid } }), succeeds: false) }
end

# Approved Nexus uploads require only the repository used by the selected consumer.
common_nexus = { 'credentialsSecretName' => 'existing-nexus', 'credentialsSecretNamespace' => 'rfe', 'serviceName' => 'nexus', 'servicePort' => 8081, 'httpScheme' => 'https' }
%w[publishIso serveKickstarts].each do |name|
  connection = common_nexus.merge(name == 'publishIso' ? { 'autoIsoRepository' => 'isos' } : { 'routeName' => 'nexus', 'routeNamespace' => 'rfe', 'kickstartRepository' => 'kickstarts' })
  values = workflow_values([name]).merge('components' => { 'nexus' => { 'mode' => 'byo', 'connection' => connection, 'artifacts' => { 'upload' => true } } })
  workflow_render('rfe-pipelines', values)
  connection.delete(name == 'publishIso' ? 'autoIsoRepository' : 'kickstartRepository')
  workflow_render('rfe-pipelines', values, succeeds: false)
end

# Nested manager values do not have Helm child-chart defaults to mask malformed flags.
[nil, false, 0, ''].each do |invalid|
  workflow_render('application-manager', { 'charts' => { 'consumer' => { 'path' => 'charts/rfe-pipelines', 'values' => { 'workflows' => invalid } } } }, succeeds: false)
  workflow_render('application-manager', { 'charts' => { 'consumer' => { 'path' => 'charts/rfe-pipelines', 'values' => { 'workflows' => { 'composeImage' => invalid } } } } }, succeeds: false)
end
workflow_render('application-manager', { 'charts' => { 'consumer' => { 'path' => 'charts/rfe-pipelines', 'values' => { 'workflows' => { 'composeImage' => { 'enabled' => nil } } } } } }, succeeds: false)

# Parent ownership wins at actual local chart paths, including common.chartPath.
%w[charts/rfe-pipelines charts/rbac].each do |path|
  values = stage.merge('common' => { 'chartPath' => path }, 'charts' => { 'consumer' => { 'values' => { 'workflows' => workflow_values(['composeImage'])['workflows'], 'components' => { 'registry' => { 'connection' => { 'pullSecretName' => 'child-secret' } } } } } })
  app = workflow_render('application-manager', values).first
  child = YAML.load(app.dig('spec', 'source', 'helm', 'values'))
  workflow_assert(child['workflows'] == stage['workflows'] && child.dig('components', 'registry', 'connection', 'pullSecretName') == 'private-pull', "parent ownership lost at #{path}")
  workflow_render(path.delete_prefix('charts/'), child)
end
%w[charts/httpd charts/unrelated].each do |path|
  app = workflow_render('application-manager', workflow_values.merge('charts' => { 'consumer' => { 'path' => path } })).first
  workflow_assert(!YAML.load(app.dig('spec', 'source', 'helm', 'values')).key?('workflows'), "workflow values leaked to #{path}")
end
app = workflow_render('application-manager', stage.merge('charts' => { 'consumer' => { 'path' => 'charts/rfe-pipelines', 'chart' => 'external' } })).first
workflow_assert(!YAML.load(app.dig('spec', 'source', 'helm', 'values')).key?('workflows'), 'workflow ownership leaked to external chart')
workflow_render('application-manager', all_off.merge('charts' => { 'consumer' => { 'path' => 'charts/rfe-pipelines' } }))
workflow_render('application-manager', workflow_values(['composeImage']).merge('rhelTarget' => { 'major' => 10 }, 'charts' => { 'consumer' => { 'path' => 'charts/rfe-pipelines' } }), succeeds: false)

# Compare complete parsed default manifests with the immutable checkpoint start.
Dir.mktmpdir('workflow-baseline-') do |dir|
  FileUtils.cp_r(File.join(WORKFLOW_ROOT, 'charts'), dir)
  staged = File.join(dir, 'charts')
  FileUtils.rm_f(File.join(staged, 'rbac', 'values.schema.json'))
  paths, err, status = Open3.capture3('git', '-C', WORKFLOW_ROOT, 'ls-tree', '-r', '--name-only', '560277ffbbc605046c2dad3511bf62db9c8c4106', *%w[rfe-pipelines rbac quay nexus httpd image-builder-vm application-manager].map { |chart| "charts/#{chart}" })
  raise err unless status.success?
  paths.lines.map(&:strip).each do |path|
    content, error, success = Open3.capture3('git', '-C', WORKFLOW_ROOT, 'show', "560277ffbbc605046c2dad3511bf62db9c8c4106:#{path}")
    raise error unless success.success?
    FileUtils.mkdir_p(File.dirname(File.join(dir, path)))
    FileUtils.rm_f(File.join(dir, path))
    File.binwrite(File.join(dir, path), content)
  end
  %w[rfe-pipelines rbac quay nexus httpd image-builder-vm].each do |chart|
    workflow_assert(workflow_render(chart, chart_root: staged) == workflow_render(chart, chart == 'rbac' ? { 'deployment' => { 'mode' => 'reference-full-stack' } } : {}), "complete managed #{chart} default manifests changed")
  end
  %w[charts/rfe-pipelines charts/rbac charts/quay charts/nexus charts/httpd].each do |path|
    values = { 'charts' => { 'consumer' => { 'path' => path } } }
    workflow_assert(workflow_render('application-manager', values, chart_root: staged) == workflow_render('application-manager', values), "default managed Application for #{path} changed")
  end
end

raise WORKFLOW_FAILURES.join("\n") unless WORKFLOW_FAILURES.empty?
puts "#{WORKFLOW_CHECKS.length} workflow render checks and complete default manifest comparisons passed"
