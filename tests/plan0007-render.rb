# Local, non-mutating Helm contract checks for implemented Plan 0007 boundaries.
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


# Virtualization platform ownership and retained VM boot source.
virtualization_byo = File.join(ROOT, 'examples/values/virtualization-byo-datasource.yaml')
source_ref = ->(docs) { docs.find { |d| d['kind'] == 'VirtualMachine' }.dig('spec', 'dataVolumeTemplates', 0, 'spec', 'sourceRef') }
assert(source_ref.call(render('image-builder-vm')) == {'kind' => 'DataSource', 'name' => 'rhel8', 'namespace' => 'openshift-virtualization-os-images'}, 'default VM DataSource changed')
assert(source_ref.call(render('image-builder-vm', '-f', virtualization_byo, '--set', 'components.virtualization.connection.dataSource.name=custom-rhel,components.virtualization.connection.dataSource.namespace=existing-images')) == {'kind' => 'DataSource', 'name' => 'custom-rhel', 'namespace' => 'existing-images'}, 'BYO VM DataSource ignored')
render('image-builder-vm', '--set', 'components.virtualization.mode=disabled', succeeds: false)
render('image-builder-vm', '--set', 'components.virtualization.mode=byo', succeeds: false)
%w[name namespace].each do |field|
  render('image-builder-vm', '-f', virtualization_byo, '--set', "components.virtualization.connection.dataSource.#{field}=", succeeds: false)
end
# The explicitly enabled legacy PVC source does not consume a DataSource.
legacy = render('image-builder-vm', '--set', 'components.virtualization.mode=byo,imageBuilderVM.dataVolumeSource=pvc,imageBuilderVM.legacyPvcSource.enabled=true')
assert(source_ref.call(legacy).nil?, 'legacy PVC source became DataSource-backed')
%w[image-builder-vm].each do |chart|
  render(chart, '--set', 'components.virtualization.mode=invalid', succeeds: false)
  render(chart, '--set', 'components.virtualization.mode=true', succeeds: false)
  render(chart, '--set', 'components.virtualization.connection.dataSource.name=42', succeeds: false)
  render(chart, '--set', 'components.virtualization.connection.dataSource.namespace=false', succeeds: false)
end
%w[cnv image-builder-vm].each do |chart|
  docs = render('application-manager', '--set', "common.chartPath=charts/#{chart},charts.consumer.destinationNamespace=rfe,components.virtualization.mode=byo,components.virtualization.connection.namespace=openshift-cnv")
  child_values = YAML.load(docs.first.dig('spec', 'source', 'helm', 'values'))
  assert(child_values.dig('components', 'virtualization', 'mode') == 'byo', "#{chart} ownership lost through common.chartPath")
end

docs = render('application-manager', '--set', 'components.virtualization.mode=byo,components.virtualization.connection.namespace=existing-cnv,charts.cnv.values.components.virtualization.mode=managed,charts.cnv.values.retained=true,charts.unrelated.name=httpd')
cnv_app = docs.find { |d| d.dig('spec', 'source', 'path') == 'charts/cnv' }
cnv_values = YAML.load(cnv_app.dig('spec', 'source', 'helm', 'values'))
assert(cnv_values.dig('components', 'virtualization', 'mode') == 'byo' && cnv_values['retained'], 'parent ownership precedence or unrelated child values changed')
unrelated = docs.find { |d| d.dig('spec', 'source', 'path') == 'charts/httpd' }
assert(!YAML.load(unrelated.dig('spec', 'source', 'helm', 'values')).key?('components'), 'virtualization boundary leaked to unrelated chart')

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
  _, err, status = Open3.capture3('helm', 'dependency', 'update', File.join(staged, 'cnv'), '--skip-refresh')
  raise err unless status.success?
  cnv = render('cnv', chart_root: staged)
  assert(kinds(cnv).sort == %w[HyperConverged Namespace], 'managed CNV resources changed')
  assert(cnv.find { |d| d['kind'] == 'Namespace' }.dig('metadata', 'labels', 'helm.sh/chart') == 'namespaces-0.1.0', 'CNV namespace compatibility labels changed')
  assert(render('cnv', '-f', virtualization_byo, chart_root: staged).empty?, 'BYO CNV renders objects')
  assert(render('cnv', '--set', 'components.virtualization.mode=disabled', chart_root: staged).empty?, 'disabled CNV renders objects')
  render('cnv', '--set', 'components.virtualization.mode=byo', succeeds: false, chart_root: staged)
  render('cnv', '--set', 'components.virtualization.mode=byo,components.virtualization.connection.namespace=', succeeds: false, chart_root: staged)
  assert(render('cnv', '--set', 'components.virtualization.mode=byo,components.virtualization.connection.namespace=existing-cnv', chart_root: staged).empty?, 'CNV BYO incorrectly requires a DataSource')
  %w[components.virtualization.mode=invalid components.virtualization.mode=true components.virtualization.connection.namespace=42 components.virtualization.connection.namespace= components.virtualization.connection.dataSource.name=42 components.virtualization.connection.dataSource.namespace=false].each do |setting|
    render('cnv', '--set', setting, succeeds: false, chart_root: staged)
  end
  render('bootstrap', chart_root: staged)
  values_file = File.join(dir, 'bootstrap-values.yaml')
  File.write(values_file, YAML.dump(bootstrap_values))
  render('bootstrap', '-f', values_file, '--set', 'argocdIntegration.enabled=true', chart_root: staged)
end
puts "#{CHECKS.length} Helm render checks passed"
