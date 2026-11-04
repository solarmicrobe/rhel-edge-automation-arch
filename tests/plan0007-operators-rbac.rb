# Focused checkpoint 6 contracts; loaded after the shared render helper.
operator_rbac_check_start = CHECKS.length
operator_components = {
  'openshift-gitops-operator' => 'gitops', 'kubevirt-hyperconverged' => 'virtualization',
  'odf-operator' => 'odf', 'openshift-pipelines-operator-rh' => 'pipelines',
  'quay-operator' => 'registry', 'nexus-operator' => 'nexus'
}
operator_components.each do |operator, component|
  args = ['--set', "operator.name=#{operator},operator.channel=stable,operator.source=redhat-operators,operator.sourceNamespace=openshift-marketplace,components.pipelines.connection.namespace=existing"]
  %w[managed byo disabled].each do |mode|
    docs = render('operator', *args, '--set', "components.#{component}.mode=#{mode}")
    assert(kinds(docs).sort == (mode == 'managed' ? %w[OperatorGroup Subscription] : []), "#{operator} #{mode} ownership failed")
  end
  %w[invalid false 0].each do |invalid|
    render('operator', *args, '--set', "components.#{component}.mode=#{invalid}", succeeds: false)
  end
  ['', 'invalid', 'false', '0'].each do |invalid|
    render('application-manager', '--set', "charts.renamed.path=charts/operator,charts.renamed.values.operator.name=#{operator},charts.renamed.values.components.#{component}.mode=#{invalid}", succeeds: false)
  end
  %w[charts.renamed.path common.chartPath].each do |path|
    parent_mode = component == 'gitops' ? 'byo' : 'disabled'
    parent_args = component == 'gitops' ? ['-f', File.join(ROOT, 'examples/values/deployment-mode-byo-cluster-argocd.yaml')] : []
    app = render('application-manager', *parent_args, '--set', "#{path}=charts/operator,charts.renamed.values.operator.name=#{operator},charts.renamed.values.extra=retained,charts.renamed.values.components.#{component}.mode=managed,components.#{component}.mode=#{parent_mode}").first
    child = YAML.load(app.dig('spec', 'source', 'helm', 'values'))
    assert(child.dig('components', component, 'mode') == parent_mode && child['extra'] == 'retained', "#{operator} parent precedence/child preservation failed")
    Dir.mktmpdir('operator-parent-') do |dir|
      values = File.join(dir, 'values.yaml')
      File.write(values, child.to_yaml)
      assert(render('operator', '-f', values).empty?, "#{operator} forwarded parent ownership rendered operator objects")
    end
  end
  app = render('application-manager', '--set', "charts.renamed.path=charts/operator,charts.renamed.chart=external,charts.renamed.values.operator.name=#{operator}").first
  assert(!YAML.load(app.dig('spec', 'source', 'helm', 'values')).key?('components'), "#{operator} forwarding leaked to external chart")
end
render('application-manager', '--set', 'components.gitops.mode=disabled,charts.workload.path=charts/operator,charts.workload.values.operator.name=openshift-gitops-operator', succeeds: false)
modern = render('rbac')
assert(modern.none? { |doc| doc.dig('metadata', 'namespace').start_with?('openshift-') }, 'modern shared namespace grants rendered')
role = modern.find { |doc| doc['kind'] == 'Role' && doc.dig('metadata', 'name') == 'rfe-automation' }
expected = [
  [%w[image.openshift.io], %w[imagestreams imagestreamimports], %w[create patch list update get], nil],
  [[''], %w[secrets services configmaps], %w[create patch list update get], nil],
  [[''], %w[pods], %w[list get], nil],
  [[''], %w[pods/exec], %w[update create], nil],
  [%w[apps], %w[deployments], %w[create patch list update get], nil],
  [%w[kubevirt.io], %w[virtualmachineinstance virtualmachineinstances], %w[get list], nil],
  [%w[route.openshift.io], %w[routes], %w[create patch list update get], nil],
  [%w[security.openshift.io], %w[securitycontextconstraints], %w[use], %w[pipelines-scc]]
]
assert(role['rules'].map { |rule| rule.values_at('apiGroups', 'resources', 'verbs', 'resourceNames') } == expected, 'modern workload RBAC exact rules changed')
assert(modern.select { |doc| doc['kind'] == 'RoleBinding' }.flat_map { |doc| doc['subjects'] }.all? { |subject| subject['namespace'].nil? || subject['namespace'] == 'rfe-gitops' }, 'modern workload binding namespace wrong')
%w[deployment.mode permissions.mode].each do |field|
  %w[invalid false 0].each { |invalid| render('rbac', '--set', "#{field}=#{invalid}", succeeds: false) }
end
assert(render('rbac', '--set', 'permissions.mode=external').empty?, 'external RBAC owned resources rendered')
stage_off = render('rbac', '--set', 'workflows.stageImage.enabled=false')
assert(stage_off.none? { |doc| doc.dig('metadata', 'name').start_with?('oci-rfe-httpd') }, 'disabled stage grants rendered')
puts "#{CHECKS.length - operator_rbac_check_start} checkpoint 6 focused operator/RBAC render checks passed"
