# Isolated executable integration checks. Never uses a real cluster or kubeconfig.
require 'yaml'
require 'json'
require 'open3'
require 'tmpdir'
require 'fileutils'
ROOT = File.expand_path('..', __dir__)
checks = 0
real_helm, _, status = Open3.capture3('/bin/bash', '-c', 'command -v helm')
raise 'Helm prerequisite missing' unless status.success?
Dir.mktmpdir('rfe-init-tests-') do |dir|
  bin = File.join(dir, 'bin')
  FileUtils.mkdir_p(bin)
  log = File.join(dir, 'calls.jsonl')
  File.write(File.join(bin, 'helm'), <<~'STUB')
    #!/usr/bin/ruby
    require 'json'
    File.open(ENV.fetch('CALL_LOG'), 'a') { |f| f.puts JSON.generate(['helm', *ARGV]) }
    if ENV['FAIL_HELM'] && ARGV.include?(ENV['FAIL_HELM'])
      warn 'injected helm failure'
      exit 11
    end
    exec ENV.fetch('REAL_HELM'), *ARGV
  STUB
  File.write(File.join(bin, 'kubectl'), <<~'STUB')
    #!/usr/bin/ruby
    require 'json'
    require 'yaml'
    record = ['kubectl', *ARGV]
    record << YAML.load_stream(File.read(ARGV[ARGV.index('-f') + 1])).compact if ARGV.include?('-f')
    File.open(ENV.fetch('CALL_LOG'), 'a') { |f| f.puts JSON.generate(record) }
    if ARGV[0, 2] == ['get', 'statefulsets,deployments']
      puts JSON.generate({'items'=>%w[rfe-argocd-argocd-application-controller existing-argocd-application-controller].map { |sa| {'kind'=>'StatefulSet', 'metadata'=>{'name'=>"actual-statefulset-for-#{sa}"}, 'spec'=>{'template'=>{'spec'=>{'serviceAccountName'=>sa}}}} }})
    end
    if ENV['FAIL_KUBECTL'] && ARGV.include?(ENV['FAIL_KUBECTL'])
      warn 'injected kubectl failure'
      exit 12
    end
  STUB
  %w[helm kubectl].each { |name| File.chmod(0755, File.join(bin, name)) }
  env = {'PATH'=>"#{bin}:/usr/bin:/bin", 'REAL_HELM'=>real_helm.strip, 'CALL_LOG'=>log, 'KUBECONFIG'=>File.join(dir, 'dummy-kubeconfig')}
  File.write(env['KUBECONFIG'], "apiVersion: v1\nkind: Config\nclusters: []\ncontexts: []\nusers: []\n")
  %w[helm kubectl].each do |tool|
    resolved, _, ok = Open3.capture3(env, '/bin/bash', '-c', "command -v #{tool}")
    raise 'PATH stub resolution unsafe' unless ok.success? && resolved.strip == File.join(bin, tool)
  end
  entrypoint = File.join(ROOT, 'setup/init.sh')
  invoke = lambda do |args, success = true, extra = {}|
    File.write(log, '')
    out, err, result = Open3.capture3(env.merge(extra), '/bin/bash', entrypoint, *args)
    raise "unexpected init status #{args.inspect}: #{err}" unless result.success? == success
    checks += 1
    [out, File.readlines(log).map { |line| JSON.parse(line) }, err]
  end
  calls_for = lambda { |calls| calls.select { |c| c.first == 'kubectl' } }
  modes = %w[managed-rfe-argocd byo-rfe-argocd byo-cluster-argocd reference-full-stack]
  modes.each do |mode|
    %w[managed external].each do |ownership|
      config = File.join(dir, 'config.yaml')
      File.write(config, YAML.dump({'permissions'=>{'mode'=>ownership}}))
      args = ['--mode',mode,'--values',config,'--target-namespace','custom-gitops','--workload-namespace','custom-workload','--timeout','17s']
      out, calls, = invoke.call(args + ['--render'])
      raise 'render called cluster' unless calls_for.call(calls).empty?
      docs = YAML.load_stream(out).compact
      raise 'wrong control ownership' unless docs.count { |d| d['kind'] == 'ArgoCD' } == (mode.start_with?('byo') ? 0 : 1)
      raise 'modern operator install' if mode != 'reference-full-stack' && docs.any? { |d| d['kind'] == 'Subscription' }
      if mode != 'reference-full-stack' && ownership == 'external'
        raise 'external RBAC' if docs.any? { |d| %w[Role RoleBinding ServiceAccount ClusterRole ClusterRoleBinding].include?(d['kind']) }
      end
      _, calls, = invoke.call(args)
      cluster = calls_for.call(calls)
      first_cluster = calls.index(cluster.first)
      raise 'late render' if calls[first_cluster..-1].any? { |c| c.first == 'helm' }
      raise 'unbounded readiness' unless cluster.select { |c| %w[wait rollout].include?(c[1]) }.all? { |c| c.include?('--timeout=17s') }
      applied = cluster.select { |c| c[1] == 'apply' }.flat_map(&:last)
      if mode.start_with?('byo')
        raise 'BYO control mutation' if applied.any? { |d| %w[ArgoCD Subscription Namespace].include?(d['kind']) }
        raise 'wrong BYO controller' unless cluster.any? { |c| c[1] == 'rollout' && c.include?('actual-statefulset-for-existing-argocd-application-controller') }
      end
      if mode != 'reference-full-stack'
        app_idx = applied.index { |d| d['kind'] == 'Application' }
        raise 'admin after Application' if applied[app_idx..-1].any? { |d| d['kind'] != 'Application' }
        app = applied[app_idx]
        child = YAML.safe_load(app.dig('spec','source','helm','values'), aliases: true)
        raise 'root alias contract inconsistent' unless child.dig('deployment','mode') == mode && child.dig('permissions','mode') == ownership && child.dig('common','namespace') == 'custom-gitops' && child.dig('common','destinationNamespace') == 'custom-workload'
      end
    end
  end
  _, calls, = invoke.call(['--mode','byo-rfe-argocd','--target-namespace','shared','--workload-namespace','shared'])
  raise 'BYO same namespace mutation' if calls_for.call(calls).select { |c| c[1] == 'apply' }.flat_map(&:last).any? { |d| d['kind'] == 'Namespace' }
  [['--wat'],['--values'],['--mode','invalid'],['--timeout','0s'],['--target-namespace','bad;name'],['--workload-namespace','Upper'],['--mode','byo-rfe-argocd','--mode','managed-rfe-argocd']].each do |args|
    _, calls, = invoke.call(args, false)
    raise 'invalid arguments reached cluster' unless calls_for.call(calls).empty?
  end
  config = File.join(dir, 'invalid.yaml')
  [
    {'deployment'=>{'mode'=>'byo-rfe-argocd'},'components'=>{'gitops'=>{'mode'=>'managed'}}},
    {'components'=>{'gitops'=>{'connection'=>{'controllerServiceAccount'=>''}}}},
    {'application-manager'=>{'permissions'=>{'mode'=>'external'}}},
    {'application-manager'=>{'charts'=>{'rfe-automation'=>{'values'=>{'charts'=>{'image-builder-vm'=>{'values'=>{'namespaceOverride'=>'bad;leaf'}}}}}}}}
  ].each do |data|
    File.write(config, YAML.dump(data))
    _, calls, = invoke.call(['--values',config], false)
    raise 'invalid configuration reached cluster' unless calls_for.call(calls).empty?
  end
  _, calls, = invoke.call([], false, {'FAIL_HELM'=>'rfe-bootstrap'})
  raise 'helm failure reached cluster' unless calls_for.call(calls).empty?
  _, calls, = invoke.call([], false, {'FAIL_KUBECTL'=>'rollout'})
  cluster = calls_for.call(calls)
  raise 'failure continued later phases' unless cluster.last[1] == 'rollout' && cluster.select { |c| c[1] == 'apply' }.flat_map(&:last).none? { |d| %w[Role Application].include?(d['kind']) }
  # Missing tools fail before API calls. Keep Ruby available to invoke the wrapper.
  missing = File.join(dir, 'missing')
  FileUtils.mkdir_p(missing)
  File.symlink('/usr/bin/ruby', File.join(missing, 'ruby'))
  File.symlink('/usr/bin/dirname', File.join(missing, 'dirname'))
  _, calls, = invoke.call([], false, {'PATH'=>missing})
  raise 'missing tool reached cluster' unless calls_for.call(calls).empty?
  # A normal CLI mode conflict cannot silently select managed ownership.
  File.write(config, YAML.dump({'deployment'=>{'mode'=>'byo-rfe-argocd'}}))
  invoke.call(['--mode','managed-rfe-argocd','--values',config], false)
  # Cached dependency contents must never enter the staged, source-only render.
  fixture = File.join(dir, 'fixture')
  FileUtils.mkdir_p(File.join(fixture, 'setup'))
  FileUtils.cp_r(File.join(ROOT, 'charts'), fixture)
  %w[init.sh init.rb values-init.yaml values-modern.yaml values-modern-byo-rfe-argocd.yaml values-modern-byo-cluster-argocd.yaml values-modern-control-access.yaml].each do |name|
    FileUtils.cp(File.join(ROOT, 'setup', name), File.join(fixture, 'setup', name))
  end
  poison = File.join(fixture, 'charts/bootstrap/charts/stale-cache/Chart.yaml')
  FileUtils.mkdir_p(File.dirname(poison))
  File.write(poison, 'invalid: [cached dependency')
  entrypoint = File.join(fixture, 'setup/init.sh')
  File.write(config, YAML.dump({'permissions'=>{'mode'=>'external'}}))
  out, calls, = invoke.call(['--mode','byo-cluster-argocd','--values',config,'--render'])
  raise 'cache regression reached cluster' unless calls_for.call(calls).empty?
  docs = YAML.load_stream(out).compact
  raise 'cache regression changed external ownership' if docs.any? { |d| %w[Role RoleBinding ServiceAccount ClusterRole ClusterRoleBinding ArgoCD Subscription].include?(d['kind']) }
  child = YAML.safe_load(docs.find { |d| d['kind'] == 'Application' }.dig('spec','source','helm','values'), aliases: true)
  raise 'cache regression lost BYO contract' unless child.dig('deployment','mode') == 'byo-cluster-argocd' && child.dig('permissions','mode') == 'external' && child.dig('components','gitops','mode') == 'byo'
  raise 'source dependency cache mutated' unless File.read(poison) == 'invalid: [cached dependency'
end
puts "#{checks} isolated initialization checks passed (real Helm, stub kubectl, dummy kubeconfig)"
