# Checkpoint 7: render the actual emitted Application forest and direct admin layers.
modern_checks_start = CHECKS.length

def modern_merge(left, right)
  left.merge(right) { |_key, a, b| a.is_a?(Hash) && b.is_a?(Hash) ? modern_merge(a, b) : b }
end

def modern_yaml(path)
  YAML.safe_load(File.read(path), aliases: true)
end

def modern_render(chart, values, chart_root, release: chart, namespace: 'rfe-gitops')
  Dir.mktmpdir('modern-values-') do |dir|
    file = File.join(dir, 'values.yaml')
    File.write(file, values.empty? ? "{}\n" : YAML.dump(values))
    out, err, status = Open3.capture3('helm', 'template', release, File.join(chart_root, chart), '-n', namespace, '-f', file)
    raise "modern #{chart} failed: #{err}" unless status.success?
    CHECKS << [chart, true]
    YAML.load_stream(out).compact
  end
end

def modern_forest(apps, chart_root, records = [])
  apps.each do |app|
    assert(app['kind'] == 'Application', 'forest input must be emitted Applications')
    source = app.dig('spec', 'source')
    assert(source['repoURL'] == 'https://github.com/solarmicrobe/rhel-edge-automation-arch.git' && source['targetRevision'] == 'custom', 'Application source escaped fork/custom')
    assert(!source['chart'] && source['path'].start_with?('charts/'), 'unexpected external forest chart')
    values = YAML.safe_load(source.dig('helm', 'values'), aliases: true)
    chart = source['path'].delete_prefix('charts/')
    docs = modern_render(chart, values, chart_root, release: app.dig('metadata', 'name'), namespace: app.dig('spec', 'destination', 'namespace'))
    records << [app, values, docs]
    modern_forest(docs, chart_root, records) if chart == 'application-manager'
  end
  records
end

Dir.mktmpdir('plan0007-modern-') do |dir|
  FileUtils.cp_r(File.join(ROOT, 'charts'), dir)
  staged = File.join(dir, 'charts')
  Find.find(staged) { |path| File.unlink(path) if File.symlink?(path) }
  _, err, status = Open3.capture3('helm', 'dependency', 'update', File.join(staged, 'bootstrap'), '--skip-refresh')
  raise err unless status.success?
  base = modern_yaml(File.join(ROOT, 'setup/values-modern.yaml'))
  %w[managed-rfe-argocd byo-cluster-argocd byo-rfe-argocd].each do |mode|
    profile = mode == 'managed-rfe-argocd' ? base : modern_merge(base, modern_yaml(File.join(ROOT, "setup/values-modern-#{mode}.yaml")))
    %w[managed external].each do |ownership|
      [false, true].each do |custom|
        values = Marshal.load(Marshal.dump(profile))
        control_ns = custom ? 'custom-gitops' : values.dig('components', 'gitops', 'connection', 'namespace')
        workload_ns = custom ? 'custom-workload' : 'rfe'
        [values, values['application-manager'], values['argocdIntegration']].each do |scope|
          scope['permissions']['mode'] = ownership
          scope['components']['gitops']['connection']['namespace'] = control_ns
        end
        values['namespaceOverride'] = workload_ns
        values['rhsm']['namespace'] = workload_ns
        values['components']['nexus']['connection']['credentialsSecretNamespace'] = workload_ns
        values['components']['odf']['connection']['bucketNamespace'] = workload_ns
        values['publicationEndpoints']['httpServing']['routeNamespace'] = workload_ns
        values['publicationEndpoints']['httpServing']['podNamespace'] = workload_ns
        [values['argocd'], values['argocdIntegration']['argocd']].each do |argo|
          argo['target']['namespace'] = control_ns
          argo['access']['namespaceGrants']['namespaces'] = [workload_ns]
          argo['appProject']['destinations'] = [workload_ns, control_ns].map { |ns| {'namespace'=>ns,'server'=>'https://kubernetes.default.svc'} }
        end
        manager = values['application-manager']
        manager['common']['namespace'] = control_ns
        manager['common']['destinationNamespace'] = workload_ns
        manager['charts']['rfe-automation']['destinationNamespace'] = control_ns
        manager['charts']['rfe-automation']['values']['common']['namespace'] = control_ns
        # Explicit Bootstrap alias wiring must survive both YAML anchors and overlays.
        %w[deployment permissions components workflows publicationEndpoints rhelTarget].each do |key|
          assert(manager[key] == values[key], "#{mode} manager alias lost #{key}")
        end
        bootstrap = modern_render('bootstrap', values, staged)
        forest = modern_forest(bootstrap.select { |doc| doc['kind'] == 'Application' }, staged)
        assert(forest.map { |app, _, _| app.dig('spec', 'source', 'path') }.sort == %w[charts/application-manager charts/httpd charts/image-builder-vm charts/rfe-pipelines], 'modern forest owns unexpected chart')
        assert(forest.all? { |app, _, _| app.dig('metadata', 'namespace') == control_ns }, 'nested Application control namespace wrong')
        leaves = forest.reject { |app, _, _| app.dig('spec', 'source', 'path') == 'charts/application-manager' }.flat_map(&:last)
        forbidden = %w[Namespace Subscription OperatorGroup CatalogSource BuildConfig ImageStream ServiceAccount Role RoleBinding ClusterRole ClusterRoleBinding AppProject ArgoCD]
        assert(leaves.none? { |doc| forbidden.include?(doc['kind']) }, 'workload forest owns admin/platform/build objects')
        assert(leaves.all? { |doc| doc.dig('metadata', 'namespace') == workload_ns }, 'workload resource namespace wrong')
        vm = leaves.find { |doc| doc['kind'] == 'VirtualMachine' }
        assert(vm.dig('spec', 'dataVolumeTemplates', 0, 'spec', 'sourceRef', 'kind') == 'DataSource', 'modern VM lost DataSource')
        job = leaves.find { |doc| doc['kind'] == 'Job' }
        container = job.dig('spec', 'template', 'spec', 'containers', 0)
        env = container['env'].to_h { |entry| [entry['name'], entry['value']] }
        assert(env['GIT_URL'] == 'https://github.com/solarmicrobe/rhel-edge-automation-arch.git' && env['GIT_BRANCH'] == 'custom', 'actual VM setup clone wrong')
        assert(container['image'] == values.dig('ansibleRunner', 'image'), 'guest setup lost prebuilt runner image')
        assert(container['command'].last.include?("image_builder_namespace=\"#{workload_ns}\""), 'guest setup namespace missing')
        httpd = leaves.find { |doc| doc['kind'] == 'Deployment' }
        assert(httpd.dig('spec', 'template', 'spec', 'containers', 0, 'image') == values.dig('image', 'repository'), 'HTTPD prebuilt image lost')
        forest.each do |app, child, docs|
          next unless app.dig('spec', 'source', 'path') == 'charts/rfe-pipelines'
          assert(child.dig('pipelines', 'repos', 'tooling') == values.dig('pipelines', 'repos', 'tooling'), 'runtime tooling clone wrong')
          %w[rfe-oci-build-image rfe-oci-build-installer-image].each do |name|
            task = docs.find { |doc| doc['kind'] == 'Task' && doc.dig('metadata', 'name') == name }
            assert(task.dig('spec', 'steps', 0, 'args', 0).include?("image_builder_namespace=\"#{workload_ns}\""), 'managed compose namespace missing')
          end
        end
        runtime = modern_render('rbac', values, staged, namespace: workload_ns)
        control_values = modern_merge(values, modern_yaml(File.join(ROOT, 'setup/values-modern-control-access.yaml')))
        control_values['argocd']['access']['namespaceGrants']['namespaces'] = [control_ns]
        control = modern_render('argocd-integration', control_values, staged, release: 'rfe-applications-access')
        argo = modern_render('argocd', values, staged, release: 'rfe-argocd')
        assert(argo.map { |doc| doc['kind'] } == (mode == 'managed-rfe-argocd' ? ['ArgoCD'] : []), 'control plane ownership wrong')
        if mode == 'managed-rfe-argocd'
          assert(values.dig('components', 'gitops', 'connection', 'controllerServiceAccount') == "#{argo.first.dig('metadata', 'name')}-argocd-application-controller", 'managed controller identity differs from rendered CR')
        end
        admin = bootstrap.reject { |doc| doc['kind'] == 'Application' } + runtime + control + argo
        rbac_kinds = %w[ServiceAccount Role RoleBinding ClusterRole ClusterRoleBinding]
        assert(admin.none? { |doc| rbac_kinds.include?(doc['kind']) }, 'external ownership emitted RBAC') if ownership == 'external'
        assert(admin.none? { |doc| %w[ClusterRole ClusterRoleBinding Secret].include?(doc['kind']) }, 'modern admin broadened cluster access or copied Secrets')
        assert(admin.select { |doc| doc['kind'] == 'Role' }.all? { |doc| doc['rules'].none? { |rule| rule['apiGroups'].include?('*') || rule['resources'].include?('*') } }, 'wildcard modern rules')
        assert(bootstrap.count { |doc| doc['kind'] == 'AppProject' } == (mode == 'managed-rfe-argocd' ? 1 : 0), 'BYO project opt-in/default ownership wrong')
        if ownership == 'managed'
          stage = runtime.find { |doc| doc['kind'] == 'ServiceAccount' && doc.dig('metadata', 'name') == 'oci-rfe-httpd' }
          assert(stage.dig('metadata', 'namespace') == workload_ns && stage['imagePullSecrets'] == [{'name'=>'existing-registry-pull'}], 'private staging SA ownership wrong')
          control_role = control.find { |doc| doc['kind'] == 'Role' }
          assert(control_role.dig('metadata', 'namespace') == control_ns && control_role['rules'].all? { |rule| rule['apiGroups'] == ['argoproj.io'] && rule['resources'] == ['applications'] }, 'control grant exceeded Applications-only')
          workload_role = bootstrap.find { |doc| doc['kind'] == 'Role' }
          assert(workload_role.dig('metadata', 'namespace') == workload_ns && workload_role['rules'].none? { |rule| rule['apiGroups'].include?('rbac.authorization.k8s.io') || rule['apiGroups'].include?('argoproj.io') }, 'workload Argo grant owns RBAC/controlplane')
        end
      end
    end
  end
  # Compare complete defaults of touched charts against the immutable start.
  baseline = File.join(dir, 'baseline')
  FileUtils.cp_r(staged, baseline)
  paths, _, status = Open3.capture3('git', '-C', ROOT, 'diff', '--name-only', 'd96c26378a2221f1701136f1c87ecd0f1025097a', '--', 'charts')
  raise 'baseline path lookup failed' unless status.success?
  paths.lines.map(&:strip).each do |path|
    content, err, status = Open3.capture3('git', '-C', ROOT, 'show', "d96c26378a2221f1701136f1c87ecd0f1025097a:#{path}")
    raise err unless status.success?
    File.write(File.join(baseline, path.delete_prefix('charts/')), content)
  end
  %w[application-manager image-builder-vm rfe-pipelines].each do |chart|
    assert(modern_render(chart, {}, staged) == modern_render(chart, {}, baseline), "#{chart} complete default changed")
  end
end
%w[image-builder-vm rfe-pipelines].each do |chart|
  ['bad;command', '$(printf shell-injection)', '`printf shell-injection`', 'UpperCase', 'a' * 64, ''].each do |namespace|
    render(chart, '--set-string', "namespaceOverride=#{namespace}", succeeds: false)
  end
  %w[false 42].each { |namespace| render(chart, '--set', "namespaceOverride=#{namespace}", succeeds: false) }
end
# The new nested-manager forwarding preserves parent precedence and chart boundaries.
Dir.mktmpdir('modern-forwarding-') do |dir|
  %w[charts/application-manager charts/bootstrap].each do |path|
    %w[charts.child.path common.chartPath].each do |entry|
      docs = render('application-manager', '--set', "#{entry}=#{path},charts.child.values.publicationEndpoints.registry.image.push=false,publicationEndpoints.registry.image.push=true,charts.child.values.rhelTarget.major=8,rhelTarget.major=9")
      child = YAML.load(docs.first.dig('spec', 'source', 'helm', 'values'))
      assert(child.dig('publicationEndpoints', 'registry', 'image', 'push') == true && child.dig('rhelTarget', 'major') == 9, 'nested forwarding lost parent precedence')
    end
  end
  docs = render('application-manager', '--set', 'charts.child.path=charts/application-manager,charts.child.chart=external,publicationEndpoints.registry.image.push=true,rhelTarget.major=9')
  child = YAML.load(docs.first.dig('spec', 'source', 'helm', 'values'))
  assert(!child.key?('publicationEndpoints') && !child.key?('rhelTarget'), 'nested forwarding leaked into foreign chart')
end
puts "#{CHECKS.length - modern_checks_start} checkpoint 7 recursive modern/admin render checks passed"
