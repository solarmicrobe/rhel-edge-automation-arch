# Executes only local builtins: no SSH, compose, Kubernetes API, or guest mutation.
require 'tmpdir'
require 'yaml'
require 'json'
require 'open3'

root = File.expand_path('..', __dir__)
Dir.mktmpdir('plan0007-byo-inventory-') do |dir|
  result = File.join(dir, 'host-result')
  play = [{'hosts' => 'localhost', 'gather_facts' => false,
           'roles' => ['openshift-image-builder-imi'],
           'tasks' => [{'ansible.builtin.assert' => {'that' => [
             "hostvars['pipeline_target_host'].ansible_ssh_host == image_builder_host",
             "hostvars['pipeline_target_host'].ansible_ssh_port == '22'",
             "lookup('file', image_builder_host_output_file) == image_builder_host"
           ]}}]}]
  playbook = File.join(dir, 'test.yaml')
  File.write(playbook, YAML.dump(play))
  env = {'ANSIBLE_LOCAL_TEMP' => File.join(dir, 'local'), 'ANSIBLE_REMOTE_TEMP' => File.join(dir, 'remote'),
         'ANSIBLE_ROLES_PATH' => File.join(root, 'ansible', 'roles')}
  ['builder.example.com', '192.0.2.10', 'bad;command', "builder.example.com\n"].each_with_index do |host, index|
    File.unlink(result) if File.exist?(result)
    vars = {'image_builder_host' => host, 'image_builder_host_output_file' => result}
    out, err, status = Open3.capture3(env, 'ansible-playbook', '-i', 'localhost,', '-c', 'local', '-e', JSON.dump(vars), playbook)
    raise "Unexpected inventory result for #{host.inspect}: #{out}\n#{err}" unless status.success? == (index < 2)
    raise 'Invalid host produced a result' if index >= 2 && File.exist?(result)
    raise 'Managed VMI tasks were included' if out.include?('Query VirtualMachineInstances')
  end
end
# Both compose playbooks must skip the scheduler (which re-queries VMI) with an explicit host.
%w[oci-create-image oci-build-installer-image].each do |name|
  playbook = YAML.load_file(File.join(root, 'ansible', 'playbooks', "#{name}.yaml"))
  role = playbook.flat_map { |play| play['roles'] || [] }.find { |r| r['role'] == 'pipeline-scheduler' }
  raise 'Explicit host still schedules through VMI' unless role['when'] == "image_builder_host | default('') | length == 0"
end
puts '4 local Ansible inventory cases and both scheduler guards passed'
