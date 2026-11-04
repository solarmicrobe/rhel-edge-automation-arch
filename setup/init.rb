#!/usr/bin/env ruby
# Operational adapter for the existing Plan 0007 charts; no cluster reads in render mode.
require 'yaml'
require 'json'
require 'open3'
require 'tmpdir'
require 'fileutils'
require 'find'
%w[INT TERM].each { |signal| Signal.trap(signal) { raise Interrupt } }

ROOT = File.expand_path('..', __dir__)
MODES = %w[managed-rfe-argocd byo-rfe-argocd byo-cluster-argocd reference-full-stack].freeze

def merge(a, b)
  a.merge(b) { |_k, x, y| x.is_a?(Hash) && y.is_a?(Hash) ? merge(x, y) : y }
end

def read_values(path)
  data = YAML.safe_load(File.read(path), aliases: true)
  raise "values must be a mapping: #{path}" unless data.is_a?(Hash)
  data
end

def run(*args)
  out, err, status = Open3.capture3(*args)
  raise "#{args.first} #{args[1]} failed: #{err}" unless status.success?
  out
end

def tool!(name)
  raise "required tool missing: #{name}" unless ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? { |p| File.file?(File.join(p, name)) && File.executable?(File.join(p, name)) }
end

def namespace!(name)
  raise "invalid namespace: #{name.inspect}" unless name.is_a?(String) && name.length <= 63 && name.match?(/\A[a-z0-9](?:[-a-z0-9]*[a-z0-9])?\z/)
end

def write_yaml(path, data)
  File.write(path, data.empty? ? "{}\n" : YAML.dump(data))
end

# Populate unpacked dependencies from local files only, without Helm repository access.
def prepare(chart, root, active = [])
  chart = File.realpath(chart)
  root = File.realpath(root)
  raise 'local chart dependency escapes staged charts' unless chart.start_with?(root + '/')
  raise 'cyclic local chart dependency' if active.include?(chart)
  # Ignore checkout dependency caches: stale archives can override current named templates.
  FileUtils.rm_rf(File.join(chart, 'charts'))
  metadata = read_values(File.join(chart, 'Chart.yaml'))
  (metadata['dependencies'] || []).each do |dep|
    repo = dep.fetch('repository')
    raise "external dependency is not available offline: #{repo}" unless repo.start_with?('file://')
    source = File.expand_path(repo.delete_prefix('file://'), chart)
    prepare(source, root, active + [chart])
    dest = File.join(chart, 'charts', dep.fetch('name'))
    FileUtils.mkdir_p(File.dirname(dest))
    FileUtils.rm_rf(dest)
    FileUtils.cp_r(source, dest)
  end
end

def render(chart, values, namespace, release, dir, staged, extra = [])
  path = File.expand_path(chart, staged)
  raise "invalid local chart path: #{chart}" unless path.start_with?(staged + '/') && File.file?(File.join(path, 'Chart.yaml'))
  prepare(path, staged)
  file = File.join(dir, 'render-values.yaml')
  write_yaml(file, values)
  output = run('helm', 'template', release, path, '-n', namespace, '-f', file, *extra)
  YAML.parse_stream(output).children.map do |doc|
    # Psych 3 requires a stream node when emitting an individual document.
    stream = Psych::Nodes::Stream.new
    stream.children << doc
    YAML.safe_load(stream.to_yaml, aliases: true)
  end.compact
end

# Follow emitted Applications, including nested managers, using the values ArgoCD receives.
def preflight_forest(apps, dir, staged, trail = [])
  apps.each do |app|
    source = app.fetch('spec').fetch('source')
    path = source['path']
    raise 'offline preflight requires local charts/* Application sources' unless !source['chart'] && path.is_a?(String) && path.start_with?('charts/')
    identity = JSON.generate(app)
    raise 'cyclic Application forest' if trail.include?(identity) || trail.length >= 32
    helm = source['helm'] || {}
    values = {}
    (helm['valueFiles'] || []).each do |file|
      base = File.expand_path(path, File.dirname(staged))
      full = File.expand_path(file, base)
      raise 'Application values file escapes local chart' unless full.start_with?(base + '/')
      values = merge(values, read_values(full))
    end
    values = merge(values, YAML.safe_load(helm['values'], aliases: true) || {}) if helm['values']
    values = merge(values, helm['valuesObject']) if helm['valuesObject']
    extra = (helm['parameters'] || []).flat_map { |p| [p['forceString'] ? '--set-string' : '--set', "#{p.fetch('name')}=#{p.fetch('value')}"] }
    docs = render(path.delete_prefix('charts/'), values, app.dig('spec', 'destination', 'namespace'), app.dig('metadata', 'name'), dir, staged, extra)
    preflight_forest(docs.select { |d| d['kind'] == 'Application' }, dir, staged, trail + [identity])
  end
end

begin
  options = {files: [], timeout: '300s', render: false}
  args = ARGV.dup
  until args.empty?
    flag = args.shift
    if flag == '--render'
      options[:render] = true
    elsif flag == '--help'
      puts 'Usage: setup/init.sh [--mode MODE] [--values FILE ...] [--target-namespace NAME] [--workload-namespace NAME] [--timeout DURATION] [--render]'
      exit
    elsif %w[--mode --values --target-namespace --workload-namespace --timeout].include?(flag)
      value = args.shift
      raise "missing value for #{flag}" if !value || value.start_with?('--')
      key = flag.delete_prefix('--').tr('-', '_').to_sym
      if key == :values
        options[:files] << value
      else
        raise "duplicate #{flag}" if options.key?(key) && key != :timeout
        options[key] = value
      end
    else
      raise "unknown argument: #{flag}"
    end
  end
  raise 'timeout must be a positive integer followed by s, m or h' unless options[:timeout].match?(/\A[1-9][0-9]*[smh]\z/)
  supplied = options[:files].reduce({}) { |v, f| merge(v, read_values(f)) }
  supplied_mode = supplied.dig('deployment', 'mode')
  raise '--mode conflicts with supplied deployment.mode' if options[:mode] && supplied_mode && options[:mode] != supplied_mode
  mode = options[:mode] || supplied_mode || 'managed-rfe-argocd'
  raise 'invalid deployment mode' unless MODES.include?(mode)
  reference = mode == 'reference-full-stack'
  byo = mode.start_with?('byo-')
  values = read_values(File.join(__dir__, reference ? 'values-init.yaml' : 'values-modern.yaml'))
  values = merge(values, read_values(File.join(__dir__, "values-modern-#{mode}.yaml"))) if byo
  values = merge(values, supplied)
  values['deployment'] = {'mode' => mode}
  values['components'] ||= {}
  values['components']['gitops'] ||= {'mode' => 'managed', 'connection' => {}}
  gitops = values['components']['gitops']
  raise 'components.gitops.mode must agree with deployment.mode' unless gitops['mode'] == (byo ? 'byo' : 'managed')
  connection = gitops['connection'] ||= {}
  control = options[:target_namespace] || supplied.dig('components', 'gitops', 'connection', 'namespace') || supplied.dig('argocd', 'target', 'namespace') || connection['namespace'] || 'rfe-gitops'
  workload = options[:workload_namespace] || values['namespaceOverride'] || 'rfe'
  # Reference's legacy namespaceOverride selects the operator namespace, not the workload.
  workload = options[:workload_namespace] || supplied['namespaceOverride'] || 'rfe' if reference
  namespace!(control)
  namespace!(workload)
  if supplied.dig('argocd', 'access', 'namespaceGrants', 'controllerServiceAccount') && !supplied.dig('components', 'gitops', 'connection', 'controllerServiceAccount')
    connection['controllerServiceAccount'] = supplied.dig('argocd', 'access', 'namespaceGrants', 'controllerServiceAccount')
  end
  %w[application-manager argocdIntegration].each do |key|
    child = supplied[key] || {}
    {'deployment'=>{'mode'=>mode}, 'permissions'=>values['permissions'], 'components'=>{'gitops'=>gitops}}.each do |section, expected|
      next unless child[section]
      if section == 'components'
        actual = child.dig(section, 'gitops', 'mode')
        raise "conflicting #{key} GitOps ownership" if actual && actual != gitops['mode']
      else
        actual = child.dig(section, 'mode')
        raise "conflicting #{key} #{section} mode" if actual && actual != (expected || {})['mode']
      end
    end
  end
  connection['namespace'] = control
  connection['project'] ||= 'rfe'
  connection['server'] ||= 'https://kubernetes.default.svc'
  connection['controllerServiceAccount'] ||= reference ? 'argocd-argocd-application-controller' : 'rfe-argocd-argocd-application-controller' unless byo
  %w[namespace project server controllerServiceAccount].each { |k| raise "required GitOps connection missing: #{k}" unless connection[k].is_a?(String) && !connection[k].empty? }
  namespace!(connection['controllerServiceAccount'])
  values['argocd'] ||= {}
  argo = values['argocd']
  argo['target'] = {'namespace'=>control, 'project'=>connection['project'], 'server'=>connection['server']}
  argo['access'] ||= {}
  argo['access']['namespaceGrants'] ||= {}
  argo['access']['namespaceGrants']['controllerServiceAccount'] = connection['controllerServiceAccount']
  argo['access']['namespaceGrants']['namespaces'] = [workload]
  unless reference
    values['namespaceOverride'] = workload
    values['rhsm']['namespace'] = workload
    values['components']['nexus']['connection']['credentialsSecretNamespace'] = workload
    values['components']['odf']['connection']['bucketNamespace'] = workload
    values['publicationEndpoints']['httpServing']['routeNamespace'] = workload
    values['publicationEndpoints']['httpServing']['podNamespace'] = workload
    argo['appProject']['destinations'] = [workload, control].uniq.map { |ns| {'namespace'=>ns, 'server'=>connection['server']} }
    manager = values['application-manager']
    %w[deployment permissions components workflows publicationEndpoints rhelTarget].each { |k| manager[k] = values[k] }
    manager['common']['namespace'] = control
    manager['common']['project'] = connection['project']
    manager['common']['destinationNamespace'] = workload
    nested = manager['charts']['rfe-automation']
    nested['destinationNamespace'] = control
    nested['values']['common']['namespace'] = control
    nested['values']['common']['project'] = connection['project']
    leaves = nested['values']['charts']
    %w[image-builder-vm rfe-pipelines].each { |key| leaves[key]['values']['ansibleRunner'] = values['ansibleRunner'] }
    vm = leaves['image-builder-vm']['values']
    %w[gitRepository gitBranch imageBuilderVM].each { |key| vm[key] = values[key] }
    leaves['httpd']['values']['image'] = values['image']
    leaves['httpd']['values']['buildConfig'] = values['buildConfig']
    leaves['rfe-pipelines']['values']['pipelines'] = values['pipelines']
    values['argocdIntegration'] = merge(values['argocdIntegration'] || {}, {'deployment'=>values['deployment'], 'permissions'=>values['permissions'], 'components'=>values['components'], 'argocd'=>argo})
  end
  tool!('helm')
  tool!('kubectl') unless options[:render]
  Dir.mktmpdir('rfe-init-') do |dir|
    File.chmod(0700, dir)
    FileUtils.cp_r(File.join(ROOT, 'charts'), dir)
    staged = File.join(dir, 'charts')
    Find.find(staged) { |p| File.unlink(p) if File.symlink?(p) }
    phases = []
    ns_docs = []
    if reference
      ns_values = merge(values, {'namespaceOverride'=>'', 'namespaces'=>[{'name'=>'openshift-gitops-operator'}, {'name'=>control}]})
      ns_docs = render('namespaces', ns_values, control, 'rfe-gitops-namespace', dir, staged)
      phases << ['namespaces', ns_docs]
      # The operator must reconcile the selected reference control namespace.
      values['config'] ||= {}
      operator_env = values['config']['env'] ||= []
      raise 'config.env must be a list' unless operator_env.is_a?(Array)
      operator_env.reject! { |entry| entry['name'] == 'ARGOCD_CLUSTER_CONFIG_NAMESPACES' }
      operator_env << {'name'=>'ARGOCD_CLUSTER_CONFIG_NAMESPACES', 'value'=>control}
      phases << ['operator', render('operator', values, 'openshift-gitops-operator', 'openshift-gitops', dir, staged)]
    elsif !byo
      ns_docs = [{'apiVersion'=>'v1','kind'=>'Namespace','metadata'=>{'name'=>control}}]
      phases << ['namespaces', ns_docs]
    end
    argo_values = reference ? merge(values, {'namespaceOverride'=>control}) : values
    control_docs = render('argocd', argo_values, control, reference ? 'argocd' : 'rfe-argocd', dir, staged)
    if !byo
      actual = control_docs.find { |d| d['kind'] == 'ArgoCD' }
      raise 'managed controller identity must match rendered ArgoCD name' unless connection['controllerServiceAccount'] == "#{actual.dig('metadata', 'name')}-argocd-application-controller"
    end
    phases << ['control-plane', control_docs]
    unless reference
      phases << ['runtime-access', render('rbac', values, workload, 'rfe-runtime-access', dir, staged)]
      access = merge(values, read_values(File.join(__dir__, 'values-modern-control-access.yaml')))
      access['argocd']['access']['namespaceGrants']['namespaces'] = [control]
      phases << ['applications-access', render('argocd-integration', access, control, 'rfe-applications-access', dir, staged)]
    end
    boot = render('bootstrap', values, control, 'rfe-bootstrap', dir, staged)
    apps, admin = boot.partition { |d| d['kind'] == 'Application' }
    # BYO target namespaces belong to their existing owner, including target == workload.
    raise 'BYO Bootstrap must not mutate target Namespace' if byo && admin.any? { |d| d['kind'] == 'Namespace' && d.dig('metadata', 'name') == control }
    phases << ['bootstrap-admin', admin]
    phases << ['workload-applications', apps]
    preflight_forest(apps, dir, staged)
    if options[:render]
      phases.each do |name, docs|
        puts "# phase: #{name}"
        docs.each { |doc| puts YAML.dump(doc) }
      end
    else
      # All local rendering and descendant validation completed before this first API call.
      wait_crd = lambda { run('kubectl', 'wait', 'crd/argocds.argoproj.io', '--for=condition=Established', "--timeout=#{options[:timeout]}") }
      wait_controller = lambda do
        seconds = options[:timeout].to_i * {'s'=>1, 'm'=>60, 'h'=>3600}.fetch(options[:timeout][-1])
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
        loop do
          remaining = (deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)).ceil
          raise 'controller readiness timeout: no StatefulSet or Deployment uses configured controller ServiceAccount' if remaining <= 0
          data = JSON.parse(run('kubectl', 'get', 'statefulsets,deployments', '-n', control, '-o', 'json', "--request-timeout=#{remaining}s"))
          controllers = data.fetch('items').select { |item| item.dig('spec', 'template', 'spec', 'serviceAccountName') == connection['controllerServiceAccount'] }
          unless controllers.empty?
            controllers.sort_by { |item| [item.fetch('kind'), item.dig('metadata', 'name')] }.each do |controller|
              remaining = (deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)).ceil
              raise 'controller readiness timeout' if remaining <= 0
              run('kubectl', 'rollout', 'status', controller.fetch('kind').downcase, controller.dig('metadata', 'name'), '-n', control, "--timeout=#{remaining}s", "--request-timeout=#{remaining}s")
              raise 'controller readiness timeout' if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
            end
            break
          end
          raise 'controller readiness timeout: no StatefulSet or Deployment uses configured controller ServiceAccount' if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
          sleep 1
        end
      end
      wait_crd.call unless reference
      if byo
        run('kubectl', 'get', 'namespace', control)
        wait_controller.call
      end
      phases.each_with_index do |(name, docs), i|
        unless docs.empty?
          file = File.join(dir, "phase-#{i}.yaml")
          File.write(file, docs.map { |d| YAML.dump(d) }.join)
          run('kubectl', 'apply', '-f', file)
        end
        wait_crd.call if name == 'operator'
        wait_controller.call if name == 'control-plane' && !byo
      end
    end
  end
rescue StandardError => e
  warn "rfe-init: #{e.message}"
  exit 1
end
