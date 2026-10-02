# Local, non-mutating Helm contract checks for the first Plan 0007 component set.
require 'yaml'
require 'open3'
require 'tmpdir'
require 'fileutils'
require 'find'

ROOT = File.expand_path('..', __dir__)
MODES = %w[managed-rfe-argocd byo-cluster-argocd byo-rfe-argocd reference-full-stack]
CHECKS = []

def render(chart, *args, succeeds: true, chart_root: File.join(ROOT, 'charts'))
  out, err, status = Open3.capture3('helm', 'template', chart, File.join(chart_root, chart), '--namespace', 'rfe-gitops', *args)
  raise "#{chart} unexpected render result: #{err}" unless status.success? == succeeds
  CHECKS << [chart, succeeds]
  succeeds ? YAML.load_stream(out).compact : err
end

def assert(condition, message)
  raise message unless condition
end

def kinds(docs)
  docs.map { |doc| doc['kind'] }
end

%w[application-manager argocd-integration argocd odf image-builder-vm rfe-pipelines].each { |chart| render(chart) }
%w[application-manager argocd-integration argocd].each do |chart|
  %w[deployment.mode permissions.mode components.gitops.mode].each do |key|
    render(chart, '--set', "#{key}=invalid", succeeds: false)
  end
  render(chart, '--set', 'deployment.mode=byo-cluster-argocd', succeeds: false)
  render(chart, '--set', 'deployment.mode=byo-cluster-argocd,components.gitops.mode=managed', succeeds: false)
  assert(render(chart, '--set', 'deployment.mode=byo-cluster-argocd,components.gitops.mode=disabled').empty?, "#{chart} disabled GitOps renders objects")
end

vm = render('image-builder-vm', '--set', 'ansibleRunner.image=registry.example.com/rfe/runner:v1')
vm_resource = vm.find { |d| d['kind'] == 'VirtualMachine' }
assert(vm_resource.dig('spec', 'dataVolumeTemplates', 0, 'spec', 'sourceRef', 'kind') == 'DataSource', 'modern VM source changed')
assert(vm.none? { |d| d.dig('metadata', 'name').to_s.include?('downloader') }, 'legacy downloader rendered')
assert(vm.any? { |d| d['kind'] == 'Job' && d.dig('spec', 'template', 'spec', 'containers', 0, 'image') == 'registry.example.com/rfe/runner:v1' }, 'existing runner image ignored')

MODES.each do |mode|
  values = File.join(ROOT, "examples/values/deployment-mode-#{mode}.yaml")
  docs = render('argocd', '-f', values)
  assert(kinds(docs) == (mode.start_with?('byo') ? [] : ['ArgoCD']), "#{mode} control plane ownership")
  assert(!kinds(docs).include?('ClusterRoleBinding'), 'default grants cluster privileges')
  docs = render('odf', '-f', values)
  assert(docs.empty?, 'BYO ODF mutates objects') unless mode == 'reference-full-stack'
  render('argocd-integration', '-f', values)
  docs = render('application-manager', '-f', values, '--set', 'charts.argocd.destinationNamespace=rfe-gitops')
  app = docs.first
  assert(app.dig('metadata', 'namespace') == (mode == 'byo-cluster-argocd' ? 'openshift-gitops' : 'rfe-gitops'), 'GitOps connection namespace ignored')
  assert(app.dig('spec', 'project') == 'rfe', 'GitOps connection project ignored')
  assert(app.dig('spec', 'source', 'path') == 'charts/argocd', 'keyed chart path broken')
  child_values = YAML.load(app.dig('spec', 'source', 'helm', 'values'))
  assert(child_values.dig('deployment', 'mode') == mode, 'child deployment mode lost')
end

byo = File.join(ROOT, 'examples/values/deployment-mode-byo-cluster-argocd.yaml')
grants = ['-f', byo, '--set', 'argocd.access.namespaceGrants.create=true,argocd.access.namespaceGrants.namespaces[0]=rfe']
assert(render('argocd-integration', *grants).empty?, 'BYO auto renders RBAC')
assert(render('argocd-integration', *grants, '--set', 'permissions.mode=external,argocd.access.clusterCapabilities.create=true').empty?, 'external ownership renders RBAC')
docs = render('argocd-integration', '-f', byo, '--set', 'argocd.appProject.create=true,argocd.appProject.sourceRepos[0]=https://example.com/rfe.git,argocd.appProject.destinations[0].namespace=rfe,argocd.appProject.destinations[0].server=https://kubernetes.default.svc')
assert(kinds(docs) == ['AppProject'], 'explicit BYO AppProject creation lost under external ownership')
docs = render('argocd-integration', *grants, '--set', 'permissions.mode=managed')
assert(kinds(docs).sort == %w[Role RoleBinding], 'managed namespace grants missing')
assert(docs.find { |d| d['kind'] == 'RoleBinding' }.dig('subjects', 0, 'namespace') == 'openshift-gitops', 'wrong controller namespace')
role = docs.find { |d| d['kind'] == 'Role' }
assert(role['rules'].none? { |r| r.values.flatten.include?('*') }, 'managed namespace rules have wildcards')
%w[argocd.appProject.create argocd.access.namespaceGrants.create argocd.access.clusterCapabilities.create].each do |key|
  render('argocd-integration', '--set-string', "#{key}=false", succeeds: false)
end
docs = render('argocd', '--set', 'deployment.mode=reference-full-stack,argocd.clusterAdmin.create=true,components.gitops.connection.namespace=other-gitops')
assert(docs.find { |d| d['kind'] == 'ClusterRoleBinding' }['subjects'].all? { |s| s['namespace'] == 'other-gitops' }, 'legacy grant points to wrong namespace')
render('argocd', '--set-string', 'argocd.clusterAdmin.create=false', succeeds: false)
render('odf', '--set', 'components.odf.mode=invalid', succeeds: false)
render('odf', '--set', 'components.odf.mode=byo', succeeds: false)
assert(render('odf', '--set', 'components.odf.mode=disabled').empty?, 'disabled ODF renders objects')
render('application-manager', '-f', byo, '--set', 'components.gitops.mode=disabled,charts.argocd.name=argocd', succeeds: false)

docs = render('application-manager', '-f', byo, '--set', 'common.chartPath=charts/argocd,charts.controlplane.destinationNamespace=rfe-gitops')
assert(YAML.load(docs.first.dig('spec', 'source', 'helm', 'values')).dig('deployment', 'mode') == 'byo-cluster-argocd', 'common.chartPath bypasses ownership')

docs = render('application-manager', '-f', byo, '--set', 'charts.bootstrap.name=bootstrap')
bootstrap_values = YAML.load(docs.first.dig('spec', 'source', 'helm', 'values'))
%w[application-manager argocdIntegration].each do |child|
  assert(bootstrap_values.dig(child, 'deployment', 'mode') == 'byo-cluster-argocd', 'bootstrap subchart ownership lost')
end

Dir.mktmpdir('plan0007-render-') do |dir|
  FileUtils.cp_r(File.join(ROOT, 'charts'), dir)
  staged = File.join(dir, 'charts')
  Find.find(staged) { |path| File.unlink(path) if File.symlink?(path) }
  # Broken local credential links are excluded; these fixtures contain no keys.
  ssh = File.join(staged, 'bootstrap', 'files', 'ssh')
  FileUtils.rm_rf(ssh)
  FileUtils.mkdir_p(ssh)
  %w[image-builder-ssh-private-key image-builder-ssh-public-key].each { |name| File.write(File.join(ssh, name), 'render-test-fixture') }
  _, err, status = Open3.capture3('helm', 'dependency', 'update', File.join(staged, 'bootstrap'))
  raise err unless status.success?
  render('bootstrap', chart_root: staged)
  values_file = File.join(dir, 'bootstrap-values.yaml')
  File.write(values_file, YAML.dump(bootstrap_values))
  render('bootstrap', '-f', values_file, '--set', 'argocdIntegration.enabled=true', chart_root: staged)
end
puts "#{CHECKS.length} Helm render checks passed"
