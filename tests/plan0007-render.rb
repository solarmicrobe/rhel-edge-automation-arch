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
# Image Builder guest ownership and explicit SSH connection.
vm_byo = File.join(ROOT, 'examples/values/image-builder-vm-byo.yaml')
%w[byo disabled].each do |mode|
  args = ['--set', "components.imageBuilderVM.mode=#{mode},components.virtualization.mode=disabled,imageBuilderVM.dataVolumeSource=pvc,imageBuilderVM.legacyPvcSource.enabled=true,rhelTarget.major=10,imageBuilderVM.replicas=0"]
  args += ['-f', vm_byo] if mode == 'byo'
  assert(render('image-builder-vm', *args).empty?, "#{mode} guest creates resources or validates managed-only settings")
end
%w[image-builder-vm rfe-pipelines].each do |chart|
  %w[invalid true].each { |mode| render(chart, '--set', "components.imageBuilderVM.mode=#{mode}", succeeds: false) }
  render(chart, '--set', 'components.imageBuilderVM.mode=byo', succeeds: false)
  %w[host sshSecretName].each do |field|
    ['', '42', 'false', 'bad/value', '-leading', 'a..b', 'trailing.', 'a' * 64].each do |value|
      render(chart, '-f', vm_byo, '--set', "components.imageBuilderVM.connection.#{field}=#{value}", succeeds: false)
    end
  end
end
render('rfe-pipelines', '--set', 'components.imageBuilderVM.mode=disabled', succeeds: false)
assert(render('image-builder-vm', '-f', vm_byo, '--set', 'components.imageBuilderVM.connection.host=192.0.2.10').empty?, 'IPv4 BYO host rejected')
byo_pipelines = render('rfe-pipelines', '-f', vm_byo)
%w[rfe-oci-build-image rfe-oci-build-installer-image].each do |name|
  task = byo_pipelines.find { |d| d['kind'] == 'Task' && d.dig('metadata', 'name') == name }
  step = task.dig('spec', 'steps', 0)
  assert(YAML.load(step['env'].first['value']) == {'image_builder_host' => 'builder.example.com'}, 'BYO host missing from JSON extra-vars')
  assert(step['args'].first.include?('-e "$IMAGE_BUILDER_CONNECTION"'), 'BYO host is not safely passed to Ansible')
  assert(task.dig('spec', 'results').any? { |r| r['name'] == 'image-builder-host' }, 'host result contract changed')
end
%w[rfe-oci-build-image rfe-oci-build-installer-image rfe-oci-push-image rfe-oci-build-auto-iso].each do |name|
  task = byo_pipelines.find { |d| d['kind'] == 'Task' && d.dig('metadata', 'name') == name }
  assert(task.dig('spec', 'params').find { |p| p['name'] == 'image-builder-secret' }['default'] == 'existing-builder-ssh', 'BYO task secret default lost')
end
%w[rfe-oci-image-pipeline rfe-oci-iso-pipeline].each do |name|
  pipeline = byo_pipelines.find { |d| d['kind'] == 'Pipeline' && d.dig('metadata', 'name') == name }
  assert(pipeline.dig('spec', 'params').find { |p| p['name'] == 'image-builder-secret' }['default'] == 'existing-builder-ssh', 'BYO pipeline secret default lost')
  pipeline.dig('spec', 'tasks').select { |task| task['name'].match?(/build-image|push-image|build-installer-image|build-auto-iso/) }.each do |task|
    assert(task['params'].any? { |p| p['name'] == 'image-builder-secret' && p['value'] == '$(params.image-builder-secret)' }, 'BYO secret not shared across pipeline tasks')
  end
end
app = render('application-manager', '-f', vm_byo, '--set', 'common.chartPath=charts/rfe-pipelines,charts.consumer.destinationNamespace=rfe').first
assert(YAML.load(app.dig('spec', 'source', 'helm', 'values')).dig('components', 'imageBuilderVM', 'connection', 'host') == 'builder.example.com', 'VM connection lost at actual pipeline chart path')
# Pipelines ownership applies only to its platform operator, retaining workload definitions.
pipelines_byo = File.join(ROOT, 'examples/values/pipelines-byo.yaml')
operator_args = ['--set', 'operator.name=openshift-pipelines-operator-rh,operator.channel=latest,operator.source=redhat-operators,operator.sourceNamespace=openshift-marketplace']
managed_operator = render('operator', *operator_args)
assert(kinds(managed_operator).sort == %w[OperatorGroup Subscription], 'managed Pipelines operator changed')
%w[byo disabled].each do |mode|
  docs = render('operator', *operator_args, '-f', pipelines_byo, '--set', "components.pipelines.mode=#{mode}")
  assert(docs.empty?, "#{mode} Pipelines installs platform resources")
  assert(kinds(render('operator', *operator_args, '--set', "operator.name=unrelated,components.pipelines.mode=#{mode}")).sort == %w[OperatorGroup Subscription], 'unrelated operator ownership changed')
end
managed_pipelines = render('rfe-pipelines')
byo_pipelines_platform = render('rfe-pipelines', '-f', pipelines_byo, '--set', 'defaultsConfigmap.disabled=false')
assert(byo_pipelines_platform == managed_pipelines.reject { |d| d['kind'] == 'ConfigMap' }, 'BYO changes workloads or mutates platform defaults')
%w[operator rfe-pipelines application-manager].each do |chart|
  args = chart == 'operator' ? operator_args : []
  %w[invalid true].each { |mode| render(chart, *args, '--set', "components.pipelines.mode=#{mode}", succeeds: false) }
  %w[42 false bad/namespace -leading].each do |namespace|
    render(chart, *args, '--set', "components.pipelines.connection.namespace=#{namespace}", succeeds: false)
  end
end
%w[operator rfe-pipelines application-manager].each do |chart|
  args = chart == 'operator' ? operator_args : []
  %w[components.pipelines=true components.pipelines.connection=42].each do |setting|
    render(chart, *args, '--set', setting, succeeds: false)
  end
end
%w[operator rfe-pipelines].each do |chart|
  args = chart == 'operator' ? operator_args : []
  render(chart, *args, '-f', pipelines_byo, '--set', 'components.pipelines.connection.namespace=', succeeds: false)
end
app = render('application-manager', '-f', pipelines_byo, '--set', 'common.chartPath=charts/rfe-pipelines,charts.workloads.destinationNamespace=rfe').first
assert(YAML.load(app.dig('spec', 'source', 'helm', 'values')).dig('components', 'pipelines', 'connection', 'namespace') == 'existing-pipelines', 'Pipelines workload connection not forwarded')
render('operator', *operator_args, '--set', 'components.pipelines.mode=byo', succeeds: false)
render('rfe-pipelines', '--set', 'components.pipelines.mode=byo', succeeds: false)
render('rfe-pipelines', '--set', 'components.pipelines.mode=disabled', succeeds: false)
%w[charts.operator.path=charts/operator common.chartPath=charts/operator].each do |path_setting|
  args = ['--set', "#{path_setting},charts.operator.values.operator.name=openshift-pipelines-operator-rh"]
  app = render('application-manager', '-f', pipelines_byo, *args).first
  assert(YAML.load(app.dig('spec', 'source', 'helm', 'values')).dig('components', 'pipelines', 'mode') == 'byo', 'Pipelines operator ownership not forwarded')
  render('application-manager', *args, '--set', 'components.pipelines.mode=byo', succeeds: false)
end
%w[charts/operator charts/rfe-pipelines].each do |path|
  %w[mode=invalid mode=true connection.namespace=42 connection.namespace=false connection.namespace=bad/name].each do |setting|
    render('application-manager', '--set', "charts.consumer.path=#{path},charts.consumer.values.operator.name=openshift-pipelines-operator-rh,charts.consumer.values.components.pipelines.#{setting}", succeeds: false)
  end
end
render('application-manager', '--set', 'charts.workloads.path=charts/rfe-pipelines,components.pipelines.mode=disabled', succeeds: false)
render('application-manager', '--set', 'charts.workloads.path=charts/rfe-pipelines,components.pipelines.mode=byo', succeeds: false)
['charts.operator.values.operator.name=unrelated', 'charts.operator.chart=external,charts.operator.values.operator.name=openshift-pipelines-operator-rh'].each do |setting|
  app = render('application-manager', '-f', pipelines_byo, '--set', "charts.operator.path=charts/operator,#{setting}").first
  assert(!YAML.load(app.dig('spec', 'source', 'helm', 'values')).key?('components'), 'Pipelines ownership leaked to unrelated/external operator')
end
Dir.mktmpdir('plan0007-pipelines-baseline-') do |dir|
  FileUtils.cp_r(File.join(ROOT, 'charts'), dir)
  staged = File.join(dir, 'charts')
  tracked, err, status = Open3.capture3('git', '-C', ROOT, 'ls-tree', '-r', '--name-only', '73807b99a20e798fecae7279e05e0836459151ce', 'charts/operator', 'charts/rfe-pipelines', 'charts/application-manager')
  raise err unless status.success?
  tracked.lines.map(&:strip).each do |path|
    content, err, status = Open3.capture3('git', '-C', ROOT, 'show', "73807b99a20e798fecae7279e05e0836459151ce:#{path}")
    raise err unless status.success?
    File.write(File.join(dir, path), content)
  end
  FileUtils.rm_f(File.join(staged, 'operator', 'values.schema.json'))
  assert(render('operator', *operator_args, chart_root: staged) == managed_operator, 'complete managed operator manifests changed')
  assert(render('rfe-pipelines', chart_root: staged) == managed_pipelines, 'complete managed Pipelines manifests changed')
  manager_args = ['--set', 'charts.operator.path=charts/operator,charts.operator.values.operator.name=openshift-pipelines-operator-rh']
  assert(render('application-manager', *manager_args, chart_root: staged) == render('application-manager', *manager_args), 'managed Application manifests changed')
end
# Registry lifecycle and explicit publication permission.
registry_byo = File.join(ROOT, 'examples/values/registry-byo.yaml')
assert(render('quay', '-f', registry_byo).empty?, 'BYO registry creates service/setup/RBAC')
assert(render('quay', '--set', 'components.registry.mode=disabled').empty?, 'disabled registry creates objects')
%w[quay rfe-pipelines application-manager].each do |chart|
  args = chart == 'application-manager' ? ['--set', 'charts.consumer.path=charts/quay'] : []
  %w[invalid true].each { |mode| render(chart, *args, '--set', "components.registry.mode=#{mode}", succeeds: false) }
  render(chart, *args, '--set', 'components.registry.mode=byo', succeeds: false)
  %w[imagePath publisherSecretName].each do |field|
    %w[42 false bad;command].each { |value| render(chart, *args, '-f', registry_byo, '--set', "components.registry.connection.#{field}=#{value}", succeeds: false) }
  end
end
render('rfe-pipelines', '-f', registry_byo, '--set', 'publicationEndpoints.registry.image.push=null', succeeds: false)
render('rfe-pipelines', '--set', 'components.registry.mode=disabled', succeeds: false)
render('rfe-pipelines', '--set', 'publicationEndpoints.registry.image.push=false', succeeds: false)
render('rfe-pipelines', '--set-string', 'publicationEndpoints.registry.image.push=false', succeeds: false)
registry_docs = render('rfe-pipelines', '-f', registry_byo)
repository = registry_docs.find { |d| d.dig('metadata', 'name') == 'rfe-oci-quay-repository' }
push = registry_docs.find { |d| d.dig('metadata', 'name') == 'rfe-oci-push-image' }
assert(!repository['spec'].key?('volumes'), 'BYO repository mounts setup or publisher Secret')
assert(repository.dig('spec', 'steps', 0, 'args', 0).include?('"$REGISTRY_IMAGE_PATH"') && !repository.to_s.include?('ansible-playbook'), 'BYO repository calls setup/API or allows alternate path')
assert(repository.dig('spec', 'steps', 0, 'env', 0, 'value') == 'registry.example.com/rfe/edge', 'BYO repository path lost')
assert(push.dig('spec', 'volumes').none? { |v| v['name'] == 'quay-rfe-setup' }, 'BYO push mounts setup Secret')
assert(push.dig('spec', 'volumes').find { |v| v['name'] == 'publisher' }.dig('secret', 'secretName') == 'existing-registry-publisher', 'BYO push Secret lost')
assert(push.dig('spec', 'steps', 0, 'args', 0).include?('quay_image_path="$REGISTRY_IMAGE_PATH"'), 'BYO push accepts alternate image path')
%w[charts/quay charts/rfe-pipelines].each do |path|
  app = render('application-manager', '-f', registry_byo, '--set', "common.chartPath=#{path},charts.consumer.destinationNamespace=rfe").first
  child = YAML.load(app.dig('spec', 'source', 'helm', 'values'))
  assert(child.dig('components', 'registry', 'mode') == 'byo', 'registry ownership lost at actual chart path')
  assert(child.dig('publicationEndpoints', 'registry', 'image', 'push') == true, 'publication opt-in lost')
end
render('application-manager', '-f', registry_byo, '--set', 'charts.consumer.path=charts/rfe-pipelines,publicationEndpoints.registry.image.push=false', succeeds: false)
render('application-manager', '-f', registry_byo, '--set-string', 'charts.consumer.path=charts/rfe-pipelines,publicationEndpoints.registry.image.push=false', succeeds: false)
Dir.mktmpdir('plan0007-registry-baseline-') do |dir|
  FileUtils.cp_r(File.join(ROOT, 'charts'), dir)
  staged = File.join(dir, 'charts')
  %w[quay rfe-pipelines application-manager].each do |chart|
    files, err, status = Open3.capture3('git', '-C', ROOT, 'ls-tree', '-r', '--name-only', 'cca8beefa7b0b4a473066874846eea4e4ce2fb41', "charts/#{chart}")
    raise err unless status.success?
    files.lines.map(&:strip).each do |path|
      content, err, status = Open3.capture3('git', '-C', ROOT, 'show', "cca8beefa7b0b4a473066874846eea4e4ce2fb41:#{path}")
      raise err unless status.success?
      File.write(File.join(dir, path), content)
    end
  end
  FileUtils.rm_f(File.join(staged, 'quay', 'values.schema.json'))
  %w[quay rfe-pipelines].each { |chart| assert(render(chart, chart_root: staged) == render(chart), "#{chart} complete managed manifests changed") }
  args = ['--set', 'charts.quay.path=charts/quay']
  assert(render('application-manager', *args, chart_root: staged) == render('application-manager', *args), 'managed registry Application changed')
end
%w[charts/quay charts/rfe-pipelines].each do |path|
  %w[mode=false mode=invalid connection.imagePath=42 connection.publisherSecretName=false connection.publisherSecretName=bad/name].each do |setting|
    render('application-manager', '--set', "charts.consumer.path=#{path},charts.consumer.values.components.registry.#{setting}", succeeds: false)
  end
end
puts "#{CHECKS.length} Helm render checks passed"
